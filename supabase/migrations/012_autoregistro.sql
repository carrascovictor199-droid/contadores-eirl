-- =====================================================================
-- 012_autoregistro.sql
-- Crear cuenta desde la web con RUC/DNI y datos de la empresa.
--  * Toda cuenta nueva nace con rol CLIENTE (trigger handle_new_user).
--  * El correo DEBE estar confirmado.
--  * vincular_mi_cuenta(documento):
--      1) si el estudio ya registró ese documento con el MISMO correo -> se vincula (VINCULADO);
--      2) si el documento no existe -> se crea el expediente del cliente con los datos del registro,
--         marcado "sin verificar" hasta que el personal lo confirme (CREADO);
--      3) si el documento ya existe con otro correo/cuenta -> queda una solicitud (lead) para
--         que el personal valide la identidad (PENDIENTE). Nunca se entregan datos ajenos.
-- =====================================================================

alter table public.clientes add column if not exists verificado boolean not null default true;
comment on column public.clientes.verificado is 'false = autoregistrado desde la web, pendiente de verificación por el estudio';
create index if not exists idx_clientes_verificado on public.clientes (verificado) where verificado = false;

-- El cliente no puede verificarse a sí mismo.
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
       or new.verificado is distinct from old.verificado
       or new.created_by is distinct from old.created_by then
      raise exception 'Un cliente solo puede modificar sus datos de contacto'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.vincular_mi_cuenta(p_documento text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_email      text;
  v_confirmado timestamptz;
  v_meta       jsonb;
  v_perfil     public.profiles%rowtype;
  v_cliente_id uuid;
  v_razon      text;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  if public.has_any_role(array['ADMINISTRADOR', 'CONTADOR', 'ASISTENTE']) then
    raise exception 'Solo para cuentas de cliente' using errcode = '42501';
  end if;
  if not public.validar_documento(p_documento) then
    raise exception 'Documento no válido' using errcode = '22023';
  end if;

  select u.email, u.email_confirmed_at, coalesce(u.raw_user_meta_data, '{}'::jsonb)
    into v_email, v_confirmado, v_meta
    from auth.users u where u.id = v_uid;
  if v_confirmado is null then
    raise exception 'Confirma tu correo antes de vincular tu cuenta' using errcode = '42501';
  end if;

  if exists (select 1 from public.clientes where user_id = v_uid) then
    return 'VINCULADO';
  end if;

  -- 1) Expediente ya registrado por el estudio con ese documento y ese mismo correo
  update public.clientes
     set user_id = v_uid
   where documento = p_documento and user_id is null and lower(correo) = lower(v_email)
  returning id into v_cliente_id;
  if v_cliente_id is not null then
    return 'VINCULADO';
  end if;

  select * into v_perfil from public.profiles where id = v_uid;

  -- 2) Documento no registrado: se crea el expediente con los datos del registro (sin verificar)
  if not exists (select 1 from public.clientes where documento = p_documento) then
    v_razon := nullif(trim(v_meta ->> 'razon_social'), '');
    if p_documento ~ '^[0-9]{11}$' and v_razon is null then
      raise exception 'Ingresa la razón social de tu empresa' using errcode = '22023';
    end if;
    insert into public.clientes (user_id, tipo_cliente, documento, razon_social, nombre_comercial, direccion,
                                 telefono, correo, verificado, created_by)
    values (
      v_uid,
      case when p_documento ~ '^20' then 'EMPRESA'::public.tipo_cliente else 'PERSONA_NATURAL'::public.tipo_cliente end,
      p_documento,
      left(coalesce(v_razon, v_perfil.nombre_completo), 200),
      left(nullif(trim(v_meta ->> 'nombre_comercial'), ''), 200),
      left(nullif(trim(v_meta ->> 'direccion'), ''), 300),
      v_perfil.telefono, v_email, false, v_uid
    )
    on conflict (documento) do nothing
    returning id into v_cliente_id;
    if v_cliente_id is not null then
      return 'CREADO';
    end if;
  end if;

  -- 3) El documento ya pertenece a otro expediente: el personal valida la identidad
  if v_perfil.telefono is null then
    raise exception 'Completa tu teléfono para continuar' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.leads
     where documento = p_documento and lower(correo) = lower(v_email)
       and estado in ('NUEVO', 'CONTACTADO', 'EN_NEGOCIACION')
  ) then
    insert into public.leads (nombre_completo, documento, telefono, correo, mensaje)
    values (v_perfil.nombre_completo, p_documento, v_perfil.telefono, v_email,
            'Registro desde el portal: el documento ya existe; solicita vincular su cuenta. Validar identidad.');
  end if;
  return 'PENDIENTE';
end;
$$;
revoke all on function public.vincular_mi_cuenta(text) from public, anon;
grant execute on function public.vincular_mi_cuenta(text) to authenticated, service_role;

-- La conversión de leads activa el portal si ya existe una cuenta de cliente con ese correo confirmado.
create or replace function public.convertir_lead_a_cliente(p_lead_id uuid)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_lead       public.leads%rowtype;
  v_cliente_id uuid;
  v_user       uuid;
begin
  if not public.has_any_role(array['ADMINISTRADOR', 'CONTADOR']) then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;

  select * into v_lead from public.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;

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

  if v_cliente_id is null then
    select id into v_cliente_id from public.clientes where documento = v_lead.documento;
  end if;

  update public.leads
     set estado = 'CONVERTIDO', cliente_id = v_cliente_id, convertido_at = now()
   where id = p_lead_id;

  select u.id into v_user
    from auth.users u
   where lower(u.email) = lower(v_lead.correo)
     and u.email_confirmed_at is not null
     and not exists (select 1 from public.clientes c where c.user_id = u.id)
     and not exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
                      where ur.user_id = u.id and r.codigo <> 'CLIENTE')
   limit 1;
  if v_user is not null then
    update public.clientes set user_id = v_user
     where id = v_cliente_id and user_id is null and lower(correo) = lower(v_lead.correo);
  end if;

  return v_cliente_id;
end;
$$;
revoke all on function public.convertir_lead_a_cliente(uuid) from public, anon;
grant execute on function public.convertir_lead_a_cliente(uuid) to authenticated, service_role;
