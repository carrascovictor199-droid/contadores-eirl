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
