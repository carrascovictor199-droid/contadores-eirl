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
