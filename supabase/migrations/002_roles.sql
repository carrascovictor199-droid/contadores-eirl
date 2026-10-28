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
