-- =====================================================================
-- 001_initial_schema.sql
-- Tipos enumerados y funciones base reutilizables.
-- =====================================================================

create type public.tipo_cliente         as enum ('PERSONA_NATURAL', 'EMPRESA');
create type public.estado_cliente       as enum ('ACTIVO', 'INACTIVO');
create type public.estado_lead          as enum ('NUEVO', 'CONTACTADO', 'EN_NEGOCIACION', 'CONVERTIDO', 'NO_INTERESADO');
create type public.estado_solicitud     as enum ('PENDIENTE', 'EN_REVISION', 'ATENDIDA', 'CANCELADA');
create type public.estado_contratacion  as enum ('ACTIVO', 'PAUSADO', 'FINALIZADO', 'CANCELADO');
create type public.estado_consulta_sunat as enum ('SUCCESS', 'ERROR', 'SIN_RESULTADOS', 'TIMEOUT');
create type public.tipo_notificacion    as enum ('INFO', 'SOLICITUD', 'MENSAJE', 'SERVICIO', 'SISTEMA');

-- Mantiene updated_at en cada UPDATE.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Validación de RUC peruano (11 dígitos, prefijo válido y dígito verificador módulo 11).
create or replace function public.validar_ruc(p_ruc text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  pesos int[] := array[5,4,3,2,7,6,5,4,3,2];
  suma  int := 0;
  resto int;
  dig   int;
  i     int;
begin
  if p_ruc is null or p_ruc !~ '^[0-9]{11}$' then
    return false;
  end if;
  if substr(p_ruc, 1, 2) not in ('10', '15', '16', '17', '20') then
    return false;
  end if;
  for i in 1..10 loop
    suma := suma + substr(p_ruc, i, 1)::int * pesos[i];
  end loop;
  resto := suma % 11;
  dig := 11 - resto;
  if dig = 10 then dig := 0; end if;
  if dig = 11 then dig := 1; end if;
  return dig = substr(p_ruc, 11, 1)::int;
end;
$$;

-- DNI (8 dígitos) o RUC válido.
create or replace function public.validar_documento(p_doc text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_doc ~ '^[0-9]{8}$' or public.validar_ruc(p_doc);
$$;
