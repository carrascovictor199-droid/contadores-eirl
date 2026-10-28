-- =====================================================================
-- 003_clients.sql
-- Clientes del estudio y sus empresas (datos tributarios).
-- =====================================================================

create table public.clientes (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid unique references public.profiles (id) on delete set null,
  tipo_cliente     public.tipo_cliente not null default 'PERSONA_NATURAL',
  documento        text not null,
  razon_social     text not null check (char_length(razon_social) between 1 and 200),
  nombre_comercial text check (nombre_comercial is null or char_length(nombre_comercial) <= 200),
  direccion        text check (direccion is null or char_length(direccion) <= 300),
  telefono         text check (telefono is null or telefono ~ '^[0-9+() -]{6,20}$'),
  correo           text check (correo is null or correo ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  estado           public.estado_cliente not null default 'ACTIVO',
  created_by       uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint clientes_documento_valido check (public.validar_documento(documento)),
  constraint clientes_documento_unico unique (documento)
);
create index idx_clientes_estado     on public.clientes (estado);
create index idx_clientes_created_at on public.clientes (created_at desc);
create index idx_clientes_razon      on public.clientes (lower(razon_social));
create index idx_clientes_correo     on public.clientes (lower(correo));
create trigger trg_clientes_updated before update on public.clientes
  for each row execute function public.set_updated_at();

-- Un cliente (portal) solo puede editar datos de contacto, no su identidad ni su estado.
create or replace function public.proteger_cliente()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_staff() then
    if new.documento is distinct from old.documento
       or new.user_id is distinct from old.user_id
       or new.estado is distinct from old.estado
       or new.tipo_cliente is distinct from old.tipo_cliente
       or new.razon_social is distinct from old.razon_social
       or new.created_by is distinct from old.created_by then
      raise exception 'Un cliente solo puede modificar sus datos de contacto'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger trg_clientes_proteger before update on public.clientes
  for each row execute function public.proteger_cliente();

-- Cliente vinculado al usuario autenticado (solo si el perfil está activo).
create or replace function public.current_cliente_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select c.id
  from public.clientes c
  join public.profiles p on p.id = c.user_id
  where c.user_id = auth.uid() and p.activo
  limit 1;
$$;
revoke all on function public.current_cliente_id() from public, anon;
grant execute on function public.current_cliente_id() to authenticated, service_role;

-- Empresas / contribuyentes asociados a un cliente (datos tributarios, p. ej. SUNAT).
create table public.empresas (
  id                     uuid primary key default gen_random_uuid(),
  cliente_id             uuid not null references public.clientes (id) on delete cascade,
  ruc                    text not null,
  razon_social           text not null check (char_length(razon_social) between 1 and 200),
  nombre_comercial       text check (nombre_comercial is null or char_length(nombre_comercial) <= 200),
  estado_contribuyente   text,
  condicion_contribuyente text,
  direccion_fiscal       text,
  ultima_consulta_sunat  timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint empresas_ruc_valido check (public.validar_ruc(ruc)),
  constraint empresas_ruc_unico unique (ruc)
);
create index idx_empresas_cliente on public.empresas (cliente_id);
create trigger trg_empresas_updated before update on public.empresas
  for each row execute function public.set_updated_at();
