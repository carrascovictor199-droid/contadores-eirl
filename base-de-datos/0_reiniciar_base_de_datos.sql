-- =====================================================================
-- OPCIONAL — BORRA todas las tablas del sistema (¡se pierden los datos!).
-- Úsalo solo si necesitas volver a ejecutar 1_base_de_datos_completa.sql desde cero.
-- No borra los usuarios de Authentication ni los archivos de Storage.
-- =====================================================================
drop trigger if exists on_auth_user_created on auth.users;

drop policy if exists docs_select on storage.objects;
drop policy if exists docs_insert on storage.objects;
drop policy if exists docs_update on storage.objects;
drop policy if exists docs_delete on storage.objects;

drop table if exists
  public.documentos, public.consultas_sunat, public.actividad, public.notificaciones,
  public.mensajes, public.solicitudes, public.leads, public.cliente_servicio,
  public.servicios, public.empresas, public.clientes, public.user_roles,
  public.profiles, public.roles
cascade;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'set_updated_at','validar_ruc','validar_documento','usuario_activo','has_any_role','is_admin',
      'is_contador_o_admin','is_staff','handle_new_user','proteger_profile','proteger_cliente',
      'current_cliente_id','convertir_lead_a_cliente','registrar_actividad','proteger_solicitud',
      'proteger_mensaje','proteger_notificacion','fn_solicitud_actividad','fn_mensaje_notificar',
      'fn_cliente_actividad','fn_lead_actividad','vincular_mi_cuenta')
  loop
    execute 'drop function if exists ' || r.fn || ' cascade';
  end loop;
end $$;

drop type if exists
  public.tipo_cliente, public.estado_cliente, public.estado_lead, public.estado_solicitud,
  public.estado_contratacion, public.estado_consulta_sunat, public.tipo_notificacion
cascade;
