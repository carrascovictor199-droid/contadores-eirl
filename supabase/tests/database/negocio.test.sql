-- =====================================================================
-- Pruebas pgTAP: servicios, solicitudes, mensajes, notificaciones y roles.
-- Ejecutar: supabase test db   (todo se revierte al final)
-- =====================================================================
begin;
select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'cliente.a@test.local', '{"nombre_completo":"Cliente A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'cliente.b@test.local', '{"nombre_completo":"Cliente B"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'contador@test.local',  '{"nombre_completo":"Contador"}'),
  ('00000000-0000-0000-0000-0000000000d1', 'asistente@test.local', '{"nombre_completo":"Asistente"}'),
  ('00000000-0000-0000-0000-0000000000e1', 'admin@test.local',     '{"nombre_completo":"Admin","rol":"ADMINISTRADOR"}');

select is((select count(*)::int from public.user_roles ur join public.roles r on r.id = ur.role_id
            where ur.user_id = '00000000-0000-0000-0000-0000000000e1' and r.codigo = 'ADMINISTRADOR'), 0,
  'Un rol enviado en los metadatos del usuario NO otorga privilegios');

delete from public.user_roles where user_id in
  ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000e1');
insert into public.user_roles (user_id, role_id)
  select '00000000-0000-0000-0000-0000000000c1', id from public.roles where codigo = 'CONTADOR';
insert into public.user_roles (user_id, role_id)
  select '00000000-0000-0000-0000-0000000000d1', id from public.roles where codigo = 'ASISTENTE';
insert into public.user_roles (user_id, role_id)
  select '00000000-0000-0000-0000-0000000000e1', id from public.roles where codigo = 'ADMINISTRADOR';

insert into public.clientes (id, user_id, documento, razon_social) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', '11111111', 'Cliente A'),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', '22222222', 'Cliente B');
insert into public.servicios (id, codigo, nombre, activo) values
  ('30000000-0000-0000-0000-000000000001', 'TEST_ACTIVO',   'Servicio activo',   true),
  ('30000000-0000-0000-0000-000000000002', 'TEST_INACTIVO', 'Servicio inactivo', false);
insert into public.solicitudes (id, cliente_id, asunto, estado) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-0000000000a1', 'Solicitud A', 'ATENDIDA');
insert into public.mensajes (cliente_id, remitente_id, contenido) values
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', 'Mensaje privado para B');

select is((select count(*)::int from public.user_roles ur join public.roles r on r.id = ur.role_id
            where ur.user_id = '00000000-0000-0000-0000-0000000000a1' and r.codigo = 'CLIENTE'), 1,
  'Todo usuario nuevo nace con rol CLIENTE');

-- ---------- ANON ----------
select set_config('request.jwt.claims', '', true);
set local role anon;
select is((select count(*)::int from public.servicios where codigo like 'TEST_%'), 1,
  'Visitante solo ve servicios activos');
select throws_ok($$ select count(*) from public.clientes $$, '42501', null, 'Visitante no puede leer clientes');
reset role;

-- ---------- CLIENTE A ----------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.mensajes), 0, 'Cliente A no ve mensajes de B');
select lives_ok($$ update public.solicitudes set estado = 'PENDIENTE'
                   where id = '40000000-0000-0000-0000-000000000001' $$,
  'El intento de reabrir una solicitud atendida no afecta filas (RLS)');
select is((select estado::text from public.solicitudes where id = '40000000-0000-0000-0000-000000000001'), 'ATENDIDA',
  'Cliente no puede reabrir una solicitud ya atendida');
select throws_ok($$ insert into public.mensajes (cliente_id, remitente_id, contenido)
                    values ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'x') $$,
  '42501', null, 'Cliente A no puede escribir en la conversación de B');
select throws_ok($$ insert into public.servicios (codigo, nombre) values ('HACK', 'Hack') $$,
  '42501', null, 'Cliente no puede crear servicios');
select throws_ok($$ update public.profiles set activo = false
                    where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'Un usuario no puede cambiar su propio estado activo');
reset role;

-- ---------- ASISTENTE ----------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ insert into public.clientes (documento, razon_social) values ('33333333', 'No permitido') $$,
  '42501', null, 'Asistente no puede crear clientes');
select throws_ok($$ insert into public.servicios (codigo, nombre) values ('HACK2', 'Hack') $$,
  '42501', null, 'Asistente no puede crear servicios');
reset role;

-- ---------- CONTADOR ----------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ update public.solicitudes set estado = 'EN_REVISION', respuesta = 'En proceso'
                   where id = '40000000-0000-0000-0000-000000000001' $$, 'Contador puede responder solicitudes');
select is((select count(*)::int from public.notificaciones
            where user_id = '00000000-0000-0000-0000-0000000000a1' and tipo = 'SOLICITUD'), 0,
  'Contador no lee notificaciones ajenas (solo admin)');
reset role;
select is((select count(*)::int from public.notificaciones
            where user_id = '00000000-0000-0000-0000-0000000000a1' and tipo = 'SOLICITUD'), 1,
  'Al responder se genera una notificación para el cliente');

-- ---------- ADMIN ----------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ update public.profiles set activo = false where id = '00000000-0000-0000-0000-0000000000a1' $$,
  'Administrador puede desactivar usuarios');
reset role;

select * from finish();
rollback;
