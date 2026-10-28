-- =====================================================================
-- PASO FINAL — convertir a tu usuario en ADMINISTRADOR (se ejecuta una sola vez).
-- 1) En Supabase: Authentication → Users → Add user (correo + contraseña robusta).
-- 2) Cambia el correo de abajo por el que acabas de crear y pulsa Run.
-- =====================================================================
do $$
declare
  v_correo text := 'REEMPLAZAR@correo.com';
  v_user   uuid;
begin
  select id into v_user from auth.users where lower(email) = lower(v_correo);
  if v_user is null then
    raise exception 'No existe un usuario de Auth con el correo %', v_correo;
  end if;

  delete from public.user_roles where user_id = v_user;
  insert into public.user_roles (user_id, role_id)
  select v_user, r.id from public.roles r where r.codigo = 'ADMINISTRADOR';
end $$;
