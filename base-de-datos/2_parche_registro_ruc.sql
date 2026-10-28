-- =====================================================================================
--  PARCHE: el autorregistro desde la web solo crea expediente si el RUC fue verificado en SUNAT
--  Ejecutar UNA vez en Supabase > SQL Editor (después de 1_base_de_datos_completa.sql).
--
--  Cambios respecto a vincular_mi_cuenta original:
--   * Para crear un expediente NUEVO se exige un RUC (11 dígitos), no DNI.
--   * Ese RUC debe tener una consulta SUNAT exitosa (SUCCESS) en los últimos 30 días.
--     Esa consulta solo la registra el backend (service_role) o el personal, nunca un visitante.
--   * Los demás caminos (vincular expediente existente con el mismo correo, o dejar un lead
--     para validar identidad) no cambian.
--  Así, aunque alguien llame directo a Supabase saltándose la web, un RUC inventado
--  no genera expediente ni portal.
-- =====================================================================================
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

  -- 2) Documento no registrado: solo con RUC verificado en SUNAT
  if not exists (select 1 from public.clientes where documento = p_documento) then
    if p_documento !~ '^[0-9]{11}$' then
      raise exception 'Solo se pueden registrar empresas con RUC' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.consultas_sunat
       where ruc = p_documento and estado = 'SUCCESS'
         and created_at > now() - interval '30 days'
    ) then
      raise exception 'RUC no verificado en SUNAT' using errcode = '22023';
    end if;

    v_razon := nullif(trim(v_meta ->> 'razon_social'), '');
    if v_razon is null then
      raise exception 'Ingresa la razón social de tu empresa' using errcode = '22023';
    end if;
    insert into public.clientes (user_id, tipo_cliente, documento, razon_social, nombre_comercial, direccion,
                                 telefono, correo, verificado, created_by)
    values (
      v_uid,
      case when p_documento ~ '^20' then 'EMPRESA'::public.tipo_cliente else 'PERSONA_NATURAL'::public.tipo_cliente end,
      p_documento,
      left(v_razon, 200),
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
