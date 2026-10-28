-- =====================================================================
-- 004_services.sql
-- Catálogo de servicios y servicios contratados por cliente.
-- =====================================================================

create table public.servicios (
  id          uuid primary key default gen_random_uuid(),
  codigo      text not null unique check (codigo ~ '^[A-Z0-9_]{2,40}$'),
  nombre      text not null check (char_length(nombre) between 1 and 120),
  descripcion text check (descripcion is null or char_length(descripcion) <= 1000),
  icono       text,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_servicios_activo on public.servicios (activo);
create trigger trg_servicios_updated before update on public.servicios
  for each row execute function public.set_updated_at();

create table public.cliente_servicio (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid not null references public.clientes (id) on delete cascade,
  servicio_id   uuid not null references public.servicios (id) on delete restrict,
  estado        public.estado_contratacion not null default 'ACTIVO',
  fecha_inicio  date not null default current_date,
  fecha_fin     date,
  observaciones text check (observaciones is null or char_length(observaciones) <= 1000),
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint cliente_servicio_fechas check (fecha_fin is null or fecha_fin >= fecha_inicio)
);
-- Evita contratar dos veces el mismo servicio mientras siga vigente.
create unique index uq_cliente_servicio_vigente
  on public.cliente_servicio (cliente_id, servicio_id)
  where estado in ('ACTIVO', 'PAUSADO');
create index idx_cliente_servicio_cliente  on public.cliente_servicio (cliente_id);
create index idx_cliente_servicio_servicio on public.cliente_servicio (servicio_id);
create index idx_cliente_servicio_estado   on public.cliente_servicio (estado);
create trigger trg_cliente_servicio_updated before update on public.cliente_servicio
  for each row execute function public.set_updated_at();
