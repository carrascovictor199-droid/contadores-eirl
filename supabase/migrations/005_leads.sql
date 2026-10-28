-- =====================================================================
-- 005_leads.sql
-- Captación web (leads) y conversión segura Lead -> Cliente.
-- =====================================================================

create table public.leads (
  id              uuid primary key default gen_random_uuid(),
  nombre_completo text not null check (char_length(trim(nombre_completo)) between 2 and 150),
  documento       text not null,
  empresa         text check (empresa is null or char_length(empresa) <= 200),
  telefono        text not null check (telefono ~ '^[0-9+() -]{6,20}$'),
  correo          text not null check (correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(correo) <= 254),
  servicio_id     uuid references public.servicios (id) on delete set null,
  mensaje         text check (mensaje is null or char_length(mensaje) <= 2000),
  estado          public.estado_lead not null default 'NUEVO',
  asignado_a      uuid references public.profiles (id) on delete set null,
  cliente_id      uuid unique references public.clientes (id) on delete restrict,
  convertido_at   timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint leads_documento_valido check (public.validar_documento(documento)),
  -- Un lead solo está CONVERTIDO si tiene cliente asociado (y viceversa).
  constraint leads_convertido_consistente check ((estado = 'CONVERTIDO') = (cliente_id is not null))
);
create index idx_leads_estado     on public.leads (estado);
create index idx_leads_created_at on public.leads (created_at desc);
create index idx_leads_servicio   on public.leads (servicio_id);
create index idx_leads_asignado   on public.leads (asignado_a);
create index idx_leads_documento  on public.leads (documento);
create trigger trg_leads_updated before update on public.leads
  for each row execute function public.set_updated_at();

-- Conversión atómica e idempotente: bloquea el lead, reutiliza el cliente si el
-- documento ya existe y nunca crea duplicados.
create or replace function public.convertir_lead_a_cliente(p_lead_id uuid)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_lead       public.leads%rowtype;
  v_cliente_id uuid;
begin
  if not public.has_any_role(array['ADMINISTRADOR', 'CONTADOR']) then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;

  select * into v_lead from public.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;

  -- Idempotente: si ya fue convertido, devuelve el mismo cliente.
  if v_lead.cliente_id is not null then
    return v_lead.cliente_id;
  end if;

  insert into public.clientes (tipo_cliente, documento, razon_social, telefono, correo, created_by)
  values (
    case when v_lead.documento ~ '^20' then 'EMPRESA'::public.tipo_cliente
         else 'PERSONA_NATURAL'::public.tipo_cliente end,
    v_lead.documento,
    coalesce(nullif(trim(v_lead.empresa), ''), v_lead.nombre_completo),
    v_lead.telefono,
    v_lead.correo,
    auth.uid()
  )
  on conflict (documento) do nothing
  returning id into v_cliente_id;

  -- Si el documento ya existía, se enlaza al cliente existente.
  if v_cliente_id is null then
    select id into v_cliente_id from public.clientes where documento = v_lead.documento;
  end if;

  update public.leads
     set estado = 'CONVERTIDO', cliente_id = v_cliente_id, convertido_at = now()
   where id = p_lead_id;

  return v_cliente_id;
end;
$$;
revoke all on function public.convertir_lead_a_cliente(uuid) from public, anon;
grant execute on function public.convertir_lead_a_cliente(uuid) to authenticated, service_role;
