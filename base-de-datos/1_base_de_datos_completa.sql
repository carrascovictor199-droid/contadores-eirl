-- =====================================================================
-- CONTADORES EIRL — BASE DE DATOS COMPLETA (un solo script)
-- Cómo usarlo: Supabase → SQL Editor → New query → pegar TODO este archivo → Run.
-- Ejecútalo UNA sola vez en un proyecto nuevo. Crea: tipos, tablas, funciones, registro de cuentas,
-- triggers, políticas RLS (seguridad por rol), bucket de Storage privado y el
-- catálogo de 6 servicios.  Después ejecuta 2_crear_administrador.sql.
-- Si necesitas repetirlo desde cero: primero 0_reiniciar_base_de_datos.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PARTE 001_initial_schema.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 001_initial_schema.sql
-- Tipos enumerados y funciones base reutilizables.
-- =====================================================================

create type public.tipo_cliente         as enum ('PERSONA_NATURAL', 'EMPRESA');
create type public.estado_cliente       as enum ('ACTIVO', 'INACTIVO');
create type public.estado_lead          as enum ('NUEVO', 'CONTACTADO', 'EN_NEGOCIACION', 'CONVERTIDO', 'NO_INTERESADO');
create type public.estado_solicitud     as enum ('PENDIENTE', 'EN_REVISION', 'ATENDIDA', 'CANCELADA');
create type public.estado_contratacion  as enum ('ACTIVO', 'PAUSADO', 'FINALIZADO', 'CANCELADO');
create type public.estado_consulta_sunat as enum ('SUCCESS', 'ERROR', 'SIN_RESULTADOS', 'TIMEOUT');
create type public.tipo_notificacion    as enum ('INFO', 'SOLICITUD', 'MENSAJE', 'SERVICIO', 'SISTEMA');

-- Mantiene updated_at en cada UPDATE.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Validación de RUC peruano (11 dígitos, prefijo válido y dígito verificador módulo 11).
create or replace function public.validar_ruc(p_ruc text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  pesos int[] := array[5,4,3,2,7,6,5,4,3,2];
  suma  int := 0;
  resto int;
  dig   int;
  i     int;
begin
  if p_ruc is null or p_ruc !~ '^[0-9]{11}$' then
    return false;
  end if;
  if substr(p_ruc, 1, 2) not in ('10', '15', '16', '17', '20') then
    return false;
  end if;
  for i in 1..10 loop
    suma := suma + substr(p_ruc, i, 1)::int * pesos[i];
  end loop;
  resto := suma % 11;
  dig := 11 - resto;
  if dig = 10 then dig := 0; end if;
  if dig = 11 then dig := 1; end if;
  return dig = substr(p_ruc, 11, 1)::int;
end;
$$;

-- DNI (8 dígitos) o RUC válido.
create or replace function public.validar_documento(p_doc text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_doc ~ '^[0-9]{8}$' or public.validar_ruc(p_doc);
$$;

-- ---------------------------------------------------------------------
-- PARTE 002_roles.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 002_roles.sql
-- Identidad extendida: profiles, roles, user_roles + helpers de autorización.
-- La identidad y contraseñas las gestiona Supabase Auth (auth.users).
-- =====================================================================

create table public.roles (
  id          uuid primary key default gen_random_uuid(),
  codigo      text not null unique
              check (codigo in ('ADMINISTRADOR', 'CONTADOR', 'ASISTENTE', 'CLIENTE')),
  nombre      text not null,
  descripcion text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_roles_updated before update on public.roles
  for each row execute function public.set_updated_at();

insert into public.roles (codigo, nombre, descripcion) values
  ('ADMINISTRADOR', 'Administrador', 'Administra el sistema, usuarios y configuración'),
  ('CONTADOR',      'Contador',      'Gestiona clientes, servicios, solicitudes, leads y reportes'),
  ('ASISTENTE',     'Asistente',     'Acceso limitado: consulta y seguimiento de leads'),
  ('CLIENTE',       'Cliente',       'Accede únicamente a su propia información')
on conflict (codigo) do nothing;

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  nombre_completo text not null check (char_length(nombre_completo) between 1 and 150),
  telefono        text check (telefono is null or telefono ~ '^[0-9+() -]{6,20}$'),
  activo          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index idx_profiles_activo on public.profiles (activo);
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.user_roles (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role_id    uuid not null references public.roles (id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (user_id, role_id)
);
create index idx_user_roles_role on public.user_roles (role_id);

-- ---------- Helpers de autorización (usados por las políticas RLS) ----------

create or replace function public.usuario_activo()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select p.activo from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function public.has_any_role(p_codigos text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r    on r.id = ur.role_id
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid()
      and p.activo
      and r.codigo = any (p_codigos)
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select public.has_any_role(array['ADMINISTRADOR']); $$;

create or replace function public.is_contador_o_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select public.has_any_role(array['ADMINISTRADOR', 'CONTADOR']); $$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public
as $$ select public.has_any_role(array['ADMINISTRADOR', 'CONTADOR', 'ASISTENTE']); $$;

-- Los helpers solo los usan usuarios autenticados (y el backend con service_role).
revoke all on function public.usuario_activo()        from public, anon;
revoke all on function public.has_any_role(text[])    from public, anon;
revoke all on function public.is_admin()              from public, anon;
revoke all on function public.is_contador_o_admin()   from public, anon;
revoke all on function public.is_staff()              from public, anon;
grant execute on function public.usuario_activo()        to authenticated, service_role;
grant execute on function public.has_any_role(text[])    to authenticated, service_role;
grant execute on function public.is_admin()              to authenticated, service_role;
grant execute on function public.is_contador_o_admin()   to authenticated, service_role;
grant execute on function public.is_staff()              to authenticated, service_role;

-- ---------- Alta automática de perfil al crear un usuario en Supabase Auth ----------
-- Todo usuario nuevo nace como CLIENTE. El rol NUNCA se toma de los metadatos del
-- usuario (evita escalada de privilegios): solo un ADMINISTRADOR (o el backend con
-- service_role) puede asignar otros roles.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_nombre   text := nullif(trim(new.raw_user_meta_data ->> 'nombre_completo'), '');
  v_telefono text := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
begin
  insert into public.profiles (id, nombre_completo, telefono)
  values (
    new.id,
    left(coalesce(v_nombre, split_part(coalesce(new.email, 'usuario'), '@', 1)), 150),
    case when v_telefono ~ '^[0-9+() -]{6,20}$' then v_telefono else null end
  )
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role_id)
  select new.id, r.id from public.roles r where r.codigo = 'CLIENTE'
  on conflict do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Solo un administrador (o contexto sin usuario final: backend/migraciones)
-- puede activar/desactivar perfiles.
create or replace function public.proteger_profile()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.activo is distinct from old.activo or new.id is distinct from old.id then
      raise exception 'Solo un administrador puede cambiar el estado del usuario'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger trg_profiles_proteger before update on public.profiles
  for each row execute function public.proteger_profile();

-- ---------------------------------------------------------------------
-- PARTE 003_clients.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- PARTE 004_services.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 004_services.sql
-- Catálogo de servicios y servicios contratados por cliente.
-- =====================================================================

create table public.servicios (
  id          uuid primary key default gen_random_uuid(),
  codigo      text not null unique check (codigo ~ '^[A-Z0-9_]{2,40}$'),
  nombre      text not null check (char_length(nombre) between 1 and 120),
  descripcion text check (descripcion is null or char_length(descripcion) <= 1000),
  icono       text,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_servicios_activo on public.servicios (activo);
create trigger trg_servicios_updated before update on public.servicios
  for each row execute function public.set_updated_at();

create table public.cliente_servicio (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes (id) on delete cascade,
  servicio_id   uuid not null references public.servicios (id) on delete restrict,
  estado        public.estado_contratacion not null default 'ACTIVO',
  fecha_inicio  date not null default current_date,
  fecha_fin     date,
  observaciones text check (observaciones is null or char_length(observaciones) <= 1000),
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint cliente_servicio_fechas check (fecha_fin is null or fecha_fin >= fecha_inicio)
);
-- Evita contratar dos veces el mismo servicio mientras siga vigente.
create unique index uq_cliente_servicio_vigente
  on public.cliente_servicio (cliente_id, servicio_id)
  where estado in ('ACTIVO', 'PAUSADO');
create index idx_cliente_servicio_cliente  on public.cliente_servicio (cliente_id);
create index idx_cliente_servicio_servicio on public.cliente_servicio (servicio_id);
create index idx_cliente_servicio_estado   on public.cliente_servicio (estado);
create trigger trg_cliente_servicio_updated before update on public.cliente_servicio
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- PARTE 005_leads.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- PARTE 006_solicitudes.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 006_solicitudes.sql
-- Solicitudes, mensajes, notificaciones y registro de actividad.
-- =====================================================================

create table public.solicitudes (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes (id) on delete cascade,
  servicio_id   uuid references public.servicios (id) on delete set null,
  asunto        text not null check (char_length(trim(asunto)) between 3 and 200),
  descripcion   text check (descripcion is null or char_length(descripcion) <= 4000),
  estado        public.estado_solicitud not null default 'PENDIENTE',
  asignado_a    uuid references public.profiles (id) on delete set null,
  respuesta     text check (respuesta is null or char_length(respuesta) <= 4000),
  respondida_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_solicitudes_cliente    on public.solicitudes (cliente_id);
create index idx_solicitudes_estado     on public.solicitudes (estado);
create index idx_solicitudes_servicio   on public.solicitudes (servicio_id);
create index idx_solicitudes_asignado   on public.solicitudes (asignado_a);
create index idx_solicitudes_created_at on public.solicitudes (created_at desc);
create trigger trg_solicitudes_updated before update on public.solicitudes
  for each row execute function public.set_updated_at();

create table public.mensajes (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references public.clientes (id) on delete cascade,
  solicitud_id uuid references public.solicitudes (id) on delete cascade,
  remitente_id uuid not null references public.profiles (id) on delete cascade,
  contenido    text not null check (char_length(trim(contenido)) between 1 and 4000),
  leido_at     timestamptz,
  created_at   timestamptz not null default now()
);
create index idx_mensajes_cliente   on public.mensajes (cliente_id, created_at desc);
create index idx_mensajes_solicitud on public.mensajes (solicitud_id);

create table public.notificaciones (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  titulo     text not null check (char_length(titulo) between 1 and 150),
  mensaje    text check (mensaje is null or char_length(mensaje) <= 1000),
  tipo       public.tipo_notificacion not null default 'INFO',
  leida      boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_notificaciones_user on public.notificaciones (user_id, leida, created_at desc);

create table public.actividad (
  id         uuid primary key default gen_random_uuid(),
  actor_id   uuid references public.profiles (id) on delete set null,
  accion     text not null check (char_length(accion) between 1 and 80),
  entidad    text not null check (char_length(entidad) between 1 and 60),
  entidad_id uuid,
  detalle    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index idx_actividad_created_at on public.actividad (created_at desc);
create index idx_actividad_entidad    on public.actividad (entidad, entidad_id);
create index idx_actividad_actor      on public.actividad (actor_id);

-- Único punto de escritura de actividad (nadie la inserta directamente).
create or replace function public.registrar_actividad(
  p_accion text, p_entidad text, p_entidad_id uuid, p_detalle jsonb default '{}'::jsonb
) returns void
language sql security definer
set search_path = public
as $$
  insert into public.actividad (actor_id, accion, entidad, entidad_id, detalle)
  values (auth.uid(), p_accion, p_entidad, p_entidad_id, coalesce(p_detalle, '{}'::jsonb));
$$;
revoke all on function public.registrar_actividad(text, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.registrar_actividad(text, text, uuid, jsonb) to service_role;

-- ---------- Protecciones por rol (defensa en profundidad junto a RLS) ----------

-- El cliente solo puede cancelar su solicitud pendiente; no toca nada más.
create or replace function public.proteger_solicitud()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_staff() then
    if old.estado <> 'PENDIENTE'
       or new.estado <> 'CANCELADA'
       or new.cliente_id   is distinct from old.cliente_id
       or new.servicio_id  is distinct from old.servicio_id
       or new.asunto       is distinct from old.asunto
       or new.descripcion  is distinct from old.descripcion
       or new.asignado_a   is distinct from old.asignado_a
       or new.respuesta    is distinct from old.respuesta
       or new.respondida_at is distinct from old.respondida_at then
      raise exception 'Un cliente solo puede cancelar su solicitud pendiente'
        using errcode = '42501';
    end if;
  end if;
  if new.respuesta is distinct from old.respuesta and new.respuesta is not null then
    new.respondida_at := now();
  end if;
  return new;
end;
$$;
create trigger trg_solicitudes_proteger before update on public.solicitudes
  for each row execute function public.proteger_solicitud();

-- Los mensajes son inmutables salvo marcar lectura.
create or replace function public.proteger_mensaje()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cliente_id is distinct from old.cliente_id
     or new.solicitud_id is distinct from old.solicitud_id
     or new.remitente_id is distinct from old.remitente_id
     or new.contenido is distinct from old.contenido
     or new.created_at is distinct from old.created_at then
    raise exception 'Los mensajes no se pueden modificar' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger trg_mensajes_proteger before update on public.mensajes
  for each row execute function public.proteger_mensaje();

-- En notificaciones solo se permite marcar como leída.
create or replace function public.proteger_notificacion()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.user_id is distinct from old.user_id
     or new.titulo is distinct from old.titulo
     or new.mensaje is distinct from old.mensaje
     or new.tipo is distinct from old.tipo
     or new.created_at is distinct from old.created_at then
    raise exception 'Solo se puede marcar la notificación como leída' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger trg_notificaciones_proteger before update on public.notificaciones
  for each row execute function public.proteger_notificacion();

-- ---------- Actividad y notificaciones automáticas ----------

create or replace function public.fn_solicitud_actividad()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  if tg_op = 'INSERT' then
    perform public.registrar_actividad('SOLICITUD_CREADA', 'solicitudes', new.id,
      jsonb_build_object('estado', new.estado, 'cliente_id', new.cliente_id));
  elsif new.estado is distinct from old.estado or new.respuesta is distinct from old.respuesta then
    perform public.registrar_actividad('SOLICITUD_ACTUALIZADA', 'solicitudes', new.id,
      jsonb_build_object('estado_anterior', old.estado, 'estado_nuevo', new.estado));
    select user_id into v_user from public.clientes where id = new.cliente_id;
    if v_user is not null and auth.uid() is distinct from v_user then
      insert into public.notificaciones (user_id, titulo, mensaje, tipo)
      values (v_user, 'Tu solicitud fue actualizada', 'Nuevo estado: ' || new.estado::text, 'SOLICITUD');
    end if;
  end if;
  return new;
end;
$$;
create trigger trg_solicitudes_actividad after insert or update on public.solicitudes
  for each row execute function public.fn_solicitud_actividad();

create or replace function public.fn_mensaje_notificar()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_user uuid;
begin
  select user_id into v_user from public.clientes where id = new.cliente_id;
  if v_user is not null and new.remitente_id <> v_user then
    insert into public.notificaciones (user_id, titulo, mensaje, tipo)
    values (v_user, 'Nuevo mensaje del estudio', left(new.contenido, 200), 'MENSAJE');
  end if;
  return new;
end;
$$;
create trigger trg_mensajes_notificar after insert on public.mensajes
  for each row execute function public.fn_mensaje_notificar();

create or replace function public.fn_cliente_actividad()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.registrar_actividad('CLIENTE_CREADO', 'clientes', new.id,
    jsonb_build_object('documento', new.documento));
  return new;
end;
$$;
create trigger trg_clientes_actividad after insert on public.clientes
  for each row execute function public.fn_cliente_actividad();

create or replace function public.fn_lead_actividad()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.registrar_actividad('LEAD_CREADO', 'leads', new.id, '{}'::jsonb);
  elsif new.estado is distinct from old.estado then
    perform public.registrar_actividad('LEAD_ESTADO', 'leads', new.id,
      jsonb_build_object('estado_anterior', old.estado, 'estado_nuevo', new.estado));
  end if;
  return new;
end;
$$;
create trigger trg_leads_actividad after insert or update on public.leads
  for each row execute function public.fn_lead_actividad();

-- ---------------------------------------------------------------------
-- PARTE 007_sunat_documentos.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 007_sunat_documentos.sql
-- Historial de consultas SUNAT y metadatos de documentos (archivos en Storage).
-- =====================================================================

create table public.consultas_sunat (
  id            uuid primary key default gen_random_uuid(),
  ruc           text not null check (ruc ~ '^[0-9]{11}$'),
  solicitado_por uuid references public.profiles (id) on delete set null,
  estado        public.estado_consulta_sunat not null,
  respuesta     jsonb,
  error         text check (error is null or char_length(error) <= 500),
  created_at    timestamptz not null default now()
);
create index idx_consultas_sunat_ruc     on public.consultas_sunat (ruc, created_at desc);
create index idx_consultas_sunat_usuario on public.consultas_sunat (solicitado_por);

create table public.documentos (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes (id) on delete cascade,
  nombre        text not null check (char_length(nombre) between 1 and 200),
  storage_path  text not null unique,
  mime_type     text,
  tamano_bytes  bigint check (tamano_bytes is null or tamano_bytes >= 0),
  subido_por    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);
create index idx_documentos_cliente on public.documentos (cliente_id, created_at desc);

-- ---------------------------------------------------------------------
-- PARTE 008_rls.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 008_rls.sql
-- Row Level Security. La seguridad vive en la base de datos, no en el frontend.
--
-- Matriz de permisos
--   ADMINISTRADOR : todo.
--   CONTADOR      : clientes, empresas, servicios, cliente_servicio, leads (incl. convertir),
--                   solicitudes (responder), mensajes, reportes y actividad.
--   ASISTENTE     : solo lectura de clientes/servicios/solicitudes; puede gestionar leads
--                   (estado/asignación) y enviar mensajes. No convierte leads ni edita clientes.
--   CLIENTE       : únicamente SUS datos, servicios, solicitudes, mensajes y notificaciones.
--   ANON          : solo ver servicios activos y registrar un lead (estado NUEVO).
-- El backend con service_role omite RLS: valida permisos en su propia capa.
-- =====================================================================

-- Privilegios mínimos para anon (RLS restringe además las filas).
revoke all on all tables in schema public from anon;
grant select on public.servicios to anon;
grant insert on public.leads to anon;

alter table public.roles            enable row level security;
alter table public.profiles         enable row level security;
alter table public.user_roles       enable row level security;
alter table public.clientes         enable row level security;
alter table public.empresas         enable row level security;
alter table public.servicios        enable row level security;
alter table public.cliente_servicio enable row level security;
alter table public.leads            enable row level security;
alter table public.solicitudes      enable row level security;
alter table public.mensajes         enable row level security;
alter table public.notificaciones   enable row level security;
alter table public.actividad        enable row level security;
alter table public.consultas_sunat  enable row level security;
alter table public.documentos       enable row level security;

-- ---------------- roles ----------------
create policy roles_select on public.roles for select to authenticated using (true);
create policy roles_admin_all on public.roles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- profiles ----------------
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
-- Sin INSERT/DELETE: el alta la hace el trigger sobre auth.users y la baja es lógica (activo=false).

-- ---------------- user_roles ----------------
create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public.is_staff());
create policy user_roles_admin_write on public.user_roles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- clientes ----------------
create policy clientes_select on public.clientes for select to authenticated
  using (public.is_staff() or id = public.current_cliente_id());
create policy clientes_insert_staff on public.clientes for insert to authenticated
  with check (public.is_contador_o_admin());
create policy clientes_update_staff on public.clientes for update to authenticated
  using (public.is_contador_o_admin()) with check (public.is_contador_o_admin());
create policy clientes_update_own on public.clientes for update to authenticated
  using (id = public.current_cliente_id()) with check (id = public.current_cliente_id());
-- Sin DELETE: se desactiva con estado = 'INACTIVO'.

-- ---------------- empresas ----------------
create policy empresas_select on public.empresas for select to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id());
create policy empresas_write on public.empresas for all to authenticated
  using (public.is_contador_o_admin()) with check (public.is_contador_o_admin());

-- ---------------- servicios ----------------
create policy servicios_select_public on public.servicios for select to anon, authenticated
  using (activo = true);
create policy servicios_select_staff on public.servicios for select to authenticated
  using (public.is_staff());
create policy servicios_write on public.servicios for all to authenticated
  using (public.is_contador_o_admin()) with check (public.is_contador_o_admin());

-- ---------------- cliente_servicio ----------------
create policy cliente_servicio_select on public.cliente_servicio for select to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id());
create policy cliente_servicio_write on public.cliente_servicio for all to authenticated
  using (public.is_contador_o_admin()) with check (public.is_contador_o_admin());

-- ---------------- leads ----------------
-- Captación pública: solo inserción, siempre como NUEVO y sin asignación ni cliente.
create policy leads_insert_public on public.leads for insert to anon, authenticated
  with check (estado = 'NUEVO' and asignado_a is null and cliente_id is null and convertido_at is null);
create policy leads_select_staff on public.leads for select to authenticated
  using (public.is_staff());
create policy leads_update_staff on public.leads for update to authenticated
  using (public.is_staff()) with check (public.is_staff());
create policy leads_delete_admin on public.leads for delete to authenticated
  using (public.is_admin());

-- ---------------- solicitudes ----------------
create policy solicitudes_select on public.solicitudes for select to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id());
create policy solicitudes_insert_cliente on public.solicitudes for insert to authenticated
  with check (
    cliente_id = public.current_cliente_id()
    and estado = 'PENDIENTE' and asignado_a is null and respuesta is null and respondida_at is null
  );
create policy solicitudes_insert_staff on public.solicitudes for insert to authenticated
  with check (public.is_contador_o_admin());
create policy solicitudes_update_staff on public.solicitudes for update to authenticated
  using (public.is_contador_o_admin()) with check (public.is_contador_o_admin());
-- El cliente solo puede cancelar su solicitud pendiente (lo refuerza el trigger proteger_solicitud).
create policy solicitudes_cancel_cliente on public.solicitudes for update to authenticated
  using (cliente_id = public.current_cliente_id() and estado = 'PENDIENTE')
  with check (cliente_id = public.current_cliente_id() and estado = 'CANCELADA');

-- ---------------- mensajes ----------------
create policy mensajes_select on public.mensajes for select to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id());
create policy mensajes_insert_cliente on public.mensajes for insert to authenticated
  with check (cliente_id = public.current_cliente_id() and remitente_id = auth.uid());
create policy mensajes_insert_staff on public.mensajes for insert to authenticated
  with check (public.is_staff() and remitente_id = auth.uid());
create policy mensajes_update_read on public.mensajes for update to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id())
  with check (public.is_staff() or cliente_id = public.current_cliente_id());

-- ---------------- notificaciones ----------------
create policy notificaciones_select on public.notificaciones for select to authenticated
  using ((user_id = auth.uid() and public.usuario_activo()) or public.is_admin());
create policy notificaciones_insert_staff on public.notificaciones for insert to authenticated
  with check (public.is_staff());
create policy notificaciones_update_own on public.notificaciones for update to authenticated
  using (user_id = auth.uid() and public.usuario_activo())
  with check (user_id = auth.uid());

-- ---------------- actividad ----------------
create policy actividad_select on public.actividad for select to authenticated
  using (public.is_contador_o_admin());
-- Sin INSERT/UPDATE/DELETE para usuarios: solo triggers/funciones SECURITY DEFINER.

-- ---------------- consultas_sunat ----------------
create policy consultas_sunat_select on public.consultas_sunat for select to authenticated
  using (public.is_staff());
create policy consultas_sunat_insert on public.consultas_sunat for insert to authenticated
  with check (public.is_staff() and solicitado_por = auth.uid());

-- ---------------- documentos ----------------
create policy documentos_select on public.documentos for select to authenticated
  using (public.is_staff() or cliente_id = public.current_cliente_id());
create policy documentos_insert on public.documentos for insert to authenticated
  with check (
    (public.is_staff() or cliente_id = public.current_cliente_id())
    and subido_por = auth.uid()
  );
create policy documentos_delete on public.documentos for delete to authenticated
  using (public.is_contador_o_admin());

-- ---------------------------------------------------------------------
-- PARTE 009_storage.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 009_storage.sql
-- Bucket privado de documentos de clientes + políticas en storage.objects.
-- Convención de ruta: <cliente_id>/<archivo>
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documentos-clientes', 'documentos-clientes', false, 10485760,
  array[
    'application/pdf', 'image/png', 'image/jpeg',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
on conflict (id) do nothing;

create policy docs_select on storage.objects for select to authenticated
  using (
    bucket_id = 'documentos-clientes'
    and (public.is_staff() or (storage.foldername(name))[1] = public.current_cliente_id()::text)
  );

create policy docs_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'documentos-clientes'
    and (public.is_staff() or (storage.foldername(name))[1] = public.current_cliente_id()::text)
  );

create policy docs_update on storage.objects for update to authenticated
  using (bucket_id = 'documentos-clientes' and public.is_contador_o_admin())
  with check (bucket_id = 'documentos-clientes' and public.is_contador_o_admin());

create policy docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'documentos-clientes' and public.is_contador_o_admin());

-- ---------------------------------------------------------------------
-- PARTE 010_catalogo_servicios.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 010_catalogo_servicios.sql
-- Catálogo base de servicios del estudio (datos de referencia, no datos de prueba).
-- Idempotente: se puede ejecutar varias veces.
-- =====================================================================

insert into public.servicios (codigo, nombre, descripcion, icono) values
  ('CONTABILIDAD',      'Contabilidad',               'Registro, libros contables y estados financieros de tu negocio.', 'calculator'),
  ('DECLARACIONES',     'Declaraciones tributarias',  'Preparación y presentación de declaraciones mensuales y anuales.', 'file-text'),
  ('ASESORIA_CONTABLE', 'Asesoría contable',          'Orientación contable personalizada para tomar mejores decisiones.', 'book-open'),
  ('ASESORIA_TRIBUTARIA','Asesoría tributaria',       'Planificación tributaria y cumplimiento de obligaciones con SUNAT.', 'scale'),
  ('GESTION_EMPRESARIAL','Gestión empresarial',       'Constitución, trámites y acompañamiento en la gestión de tu empresa.', 'briefcase'),
  ('OTROS',             'Otros servicios',            'Cuéntanos tu necesidad y diseñamos una solución a medida.', 'more-horizontal')
on conflict (codigo) do nothing;

-- ---------------------------------------------------------------------
-- PARTE 011_profiles_correo.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- 011_profiles_correo.sql
-- Copia del correo en profiles para listar usuarios sin acceder a auth.users.
-- =====================================================================

alter table public.profiles add column if not exists correo text;

update public.profiles p set correo = u.email
  from auth.users u where u.id = p.id and p.correo is null;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_nombre   text := nullif(trim(new.raw_user_meta_data ->> 'nombre_completo'), '');
  v_telefono text := nullif(trim(new.raw_user_meta_data ->> 'telefono'), '');
begin
  insert into public.profiles (id, nombre_completo, telefono, correo)
  values (
    new.id,
    left(coalesce(v_nombre, split_part(coalesce(new.email, 'usuario'), '@', 1)), 150),
    case when v_telefono ~ '^[0-9+() -]{6,20}$' then v_telefono else null end,
    new.email
  )
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role_id)
  select new.id, r.id from public.roles r where r.codigo = 'CLIENTE'
  on conflict do nothing;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- PARTE 012_autoregistro.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- FINAL: sincroniza usuarios que ya existan en Authentication
-- (útil si reinstalas la base; no hace nada en un proyecto nuevo)
-- ---------------------------------------------------------------------
insert into public.profiles (id, nombre_completo, correo)
select u.id,
       left(coalesce(nullif(trim(u.raw_user_meta_data ->> 'nombre_completo'), ''), split_part(coalesce(u.email, 'usuario'), '@', 1)), 150),
       u.email
from auth.users u
on conflict (id) do nothing;

insert into public.user_roles (user_id, role_id)
select p.id, r.id
from public.profiles p
cross join public.roles r
where r.codigo = 'CLIENTE'
  and not exists (select 1 from public.user_roles ur where ur.user_id = p.id);

-- Verificación rápida: debe devolver 14 tablas con RLS activo
select count(*) as tablas_con_rls
from pg_tables
where schemaname = 'public' and rowsecurity = true;
