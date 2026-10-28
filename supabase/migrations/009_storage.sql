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
