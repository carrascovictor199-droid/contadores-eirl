-- Pruebas pgTAP del registro de cuentas. Ejecutar: supabase test db
begin;
select plan(14);

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000f1', 'ana@test.local',       now(),  '{"nombre_completo":"Ana","telefono":"999111222"}'),
  ('00000000-0000-0000-0000-0000000000f2', 'otro@test.local',      now(),  '{"nombre_completo":"Otro","telefono":"999333444"}'),
  ('00000000-0000-0000-0000-0000000000f3', 'sinconfirmar@test.local', null, '{"nombre_completo":"Sin Confirmar","telefono":"999555666"}'),
  ('00000000-0000-0000-0000-0000000000f4', 'nuevo@test.local',     now(),  '{"nombre_completo":"Nuevo","telefono":"999777888"}'),
  ('00000000-0000-0000-0000-0000000000f5', 'atacante@test.local',  now(),  '{"nombre_completo":"Atacante","telefono":"999000111"}'),
  ('00000000-0000-0000-0000-0000000000f7', 'empresa@test.local',   now(),  '{"nombre_completo":"Rosa Gómez","telefono":"999222333","documento":"20100070970","razon_social":"Empresa Nueva SAC","direccion":"Av. Lima 123"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'contador@test.local',  now(),  '{"nombre_completo":"Contador"}');
delete from public.user_roles where user_id = '00000000-0000-0000-0000-0000000000c1';
insert into public.user_roles (user_id, role_id) select '00000000-0000-0000-0000-0000000000c1', id from public.roles where codigo = 'CONTADOR';

insert into public.clientes (id, documento, razon_social, correo) values
  ('10000000-0000-0000-0000-0000000000f1', '44444444', 'Ana Pérez',    'ana@test.local'),
  ('10000000-0000-0000-0000-0000000000f6', '66666666', 'Cliente Real', 'real@test.local');
insert into public.leads (id, nombre_completo, documento, telefono, correo) values
  ('20000000-0000-0000-0000-0000000000f4', 'Nuevo',     '55555555', '999777888', 'nuevo@test.local'),
  ('20000000-0000-0000-0000-0000000000f5', 'Atacante',  '66666666', '999000111', 'atacante@test.local');

-- Ana: documento y correo coinciden -> se vincula sola
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select is(public.vincular_mi_cuenta('44444444'), 'VINCULADO', 'Documento y correo coinciden: la cuenta se vincula');
reset role;
select is((select user_id::text from public.clientes where documento = '44444444'), '00000000-0000-0000-0000-0000000000f1',
  'El cliente queda ligado al usuario correcto');

-- Otro: intenta vincular el documento de Ana con SU correo -> solo queda solicitud, no obtiene acceso
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
set local role authenticated;
select is(public.vincular_mi_cuenta('44444444'), 'PENDIENTE', 'Con otro correo no se vincula: queda pendiente de validación');
select is(public.vincular_mi_cuenta('44444444'), 'PENDIENTE', 'Repetir la solicitud no falla');
reset role;
select is((select count(*)::int from public.leads where documento = '44444444' and lower(correo) = 'otro@test.local'), 1,
  'La solicitud pendiente no se duplica');

-- Cuenta sin confirmar el correo
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f3","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.vincular_mi_cuenta('77777777') $$, '42501', null, 'Sin correo confirmado no se puede vincular');
reset role;

-- Empresa nueva: se registra con su RUC y datos -> se crea su expediente (sin verificar)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f7","role":"authenticated"}', true);
set local role authenticated;
select is(public.vincular_mi_cuenta('20100070970'), 'CREADO', 'Con RUC nuevo se crea el expediente del cliente');
select is((select razon_social || ' | ' || direccion from public.clientes where documento = '20100070970'), 'Empresa Nueva SAC | Av. Lima 123',
  'Se guardan la razón social y la dirección ingresadas');
select is((select verificado from public.clientes where documento = '20100070970'), false, 'El autoregistro queda sin verificar');
select throws_ok($$ update public.clientes set verificado = true where documento = '20100070970' $$,
  '42501', null, 'El cliente no puede verificarse a sí mismo');
reset role;

-- Personal no usa este flujo
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.vincular_mi_cuenta('88888888') $$, '42501', null, 'El personal no puede usar la vinculación de clientes');

-- Conversión: activa el portal solo si el correo coincide
select lives_ok($$ select public.convertir_lead_a_cliente('20000000-0000-0000-0000-0000000000f4') $$, 'Convertir lead de visitante con cuenta');
select public.convertir_lead_a_cliente('20000000-0000-0000-0000-0000000000f5');
reset role;
select is((select user_id::text from public.clientes where documento = '55555555'), '00000000-0000-0000-0000-0000000000f4',
  'Al convertir, el portal del cliente queda activo (correo coincidente)');
select is((select user_id::text from public.clientes where documento = '66666666'), null::text,
  'Un cliente existente NO se liga a una cuenta con correo distinto');

select * from finish();
rollback;
