-- =====================================================================
-- 007_sunat_documentos.sql
-- Historial de consultas SUNAT y metadatos de documentos (archivos en Storage).
-- =====================================================================

create table public.consultas_sunat (
  id            uuid primary key default gen_random_uuid(),
  ruc           text not null check (ruc ~ '^[0-9]{11}$'),
  solicitado_por uuid references public.profiles (id) on delete set null,
  estado        public.estado_consulta_sunat not null,
  respuesta     jsonb,
  error         text check (error is null or char_length(error) <= 500),
  created_at    timestamptz not null default now()
);
create index idx_consultas_sunat_ruc     on public.consultas_sunat (ruc, created_at desc);
create index idx_consultas_sunat_usuario on public.consultas_sunat (solicitado_por);

create table public.documentos (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes (id) on delete cascade,
  nombre        text not null check (char_length(nombre) between 1 and 200),
  storage_path  text not null unique,
  mime_type     text,
  tamano_bytes  bigint check (tamano_bytes is null or tamano_bytes >= 0),
  subido_por    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);
create index idx_documentos_cliente on public.documentos (cliente_id, created_at desc);
