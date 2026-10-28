-- =====================================================================
-- Pruebas pgTAP de RLS y reglas de negocio.  Ejecutar: supabase test db
-- Todo ocurre dentro de una transacción que se revierte al final.
-- =====================================================================
begin;
select plan(20);

-- ---------- Datos de prueba (se revierten) ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'cliente.a@test.local',   '{"nombre_completo":"Cliente A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'cliente.b@test.local',   '{"nombre_completo":"Cliente B"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'contador@test.local',    '{"nombre_completo":"Contador"}'),
  ('00000000-0000-0000-0000-0000000000d1', 'asistente@test.local',   '{"nombre_completo":"Asistente"}');

delete from public.user_roles
 where user_id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
insert into public.user_roles (user_id, role_id)
  select '00000000-0000-0000-0000-0000000000c1', id from public.roles where codigo = 'CONTADOR';
insert into public.user_roles (user_id, role_id)
  select '00000000-0000-0000-0000-0000000000d1', id from public.roles where codigo = 'ASISTENTE';

insert into public.clientes (id, user_id, documento, razon_social) values
  ('10000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', '11111111', 'Cliente A'),
  ('10000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b1', '22222222', 'Cliente B');

insert into public.solicitudes (cliente_id, asunto) values
  ('10000000-0000-0000-0000-0000000000b1', 'Solicitud privada de B');

insert into public.leads (id, nombre_completo, documento, telefono, correo) values
  ('20000000-0000-0000-0000-000000000001', 'Lead Prueba', '20100070970', '999999999', 'lead@test.local');

-- ---------- Validaciones ----------
select ok(public.validar_ruc('20100070970'),  'RUC válido es aceptado');
select ok(not public.validar_ruc('20100070971'), 'RUC con dígito verificador incorrecto es rechazado');

-- ---------- CLIENTE A ----------
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*)::int from public.clientes), 1,
  'Cliente A solo ve su propio registro de cliente');
select is((select count(*)::int from public.solicitudes
            where cliente_id = '10000000-0000-0000-0000-0000000000b1'), 0,
  'Cliente A no ve solicitudes de Cliente B');
select throws_ok($$ insert into public.solicitudes (cliente_id, asunto)
                    values ('10000000-0000-0000-0000-0000000000b1', 'Intruso') $$,
  '42501', null, 'Cliente A no puede crear solicitudes a nombre de B');
select lives_ok($$ insert into public.solicitudes (cliente_id, asunto)
                   values ('10000000-0000-0000-0000-0000000000a1', 'Mi solicitud') $$,
  'Cliente A puede crear su propia solicitud');
select throws_ok($$ update public.clientes set documento = '33333333'
                    where id = '10000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'Cliente A no puede cambiar su documento');
select is((select count(*)::int from public.leads), 0, 'Cliente A no ve leads');
select throws_ok($$ insert into public.user_roles (user_id, role_id)
                    select '00000000-0000-0000-0000-0000000000a1', id
                      from public.roles where codigo = 'ADMINISTRADOR' $$,
  '42501', null, 'Cliente A no puede auto-asignarse el rol ADMINISTRADOR');
select is((select count(*)::int from public.actividad), 0, 'Cliente A no ve la actividad del sistema');
select is((select count(*)::int from public.user_roles), 1, 'Cliente A solo ve sus propios roles');
reset role;

-- ---------- ANON (visitante) ----------
select set_config('request.jwt.claims', '', true);
set local role anon;

select lives_ok($$ insert into public.leads (nombre_completo, documento, telefono, correo)
                   values ('Visitante', '12345678', '988888888', 'visitante@test.local') $$,
  'Visitante anónimo puede registrar un lead');
select throws_ok($$ insert into public.leads (nombre_completo, documento, telefono, correo, estado)
                    values ('Visitante', '12345679', '988888888', 'v2@test.local', 'CONTACTADO') $$,
  '42501', null, 'Visitante no puede crear un lead con estado distinto de NUEVO');
select throws_ok($$ select count(*) from public.leads $$,
  '42501', null, 'Visitante no puede leer leads');
reset role;

-- ---------- ASISTENTE ----------
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.convertir_lead_a_cliente('20000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'Asistente no puede convertir leads');
select ok((select count(*) from public.clientes) >= 2, 'Asistente puede consultar clientes');
reset role;

-- ---------- CONTADOR ----------
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.convertir_lead_a_cliente('20000000-0000-0000-0000-000000000001') $$,
  'Contador puede convertir un lead');
select is(public.convertir_lead_a_cliente('20000000-0000-0000-0000-000000000001'),
  (select cliente_id from public.leads where id = '20000000-0000-0000-0000-000000000001'),
  'La conversión es idempotente (mismo cliente)');
select is((select count(*)::int from public.clientes where documento = '20100070970'), 1,
  'La conversión no genera clientes duplicados');
select is((select estado::text from public.leads where id = '20000000-0000-0000-0000-000000000001'),
  'CONVERTIDO', 'El lead queda en estado CONVERTIDO');
reset role;

select * from finish();
rollback;
