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
