-- =====================================================================
-- 010_catalogo_servicios.sql
-- Catálogo base de servicios del estudio (datos de referencia, no datos de prueba).
-- Idempotente: se puede ejecutar varias veces.
-- =====================================================================

insert into public.servicios (codigo, nombre, descripcion, icono) values
  ('CONTABILIDAD',      'Contabilidad',               'Registro, libros contables y estados financieros de tu negocio.', 'calculator'),
  ('DECLARACIONES',     'Declaraciones tributarias',  'Preparación y presentación de declaraciones mensuales y anuales.', 'file-text'),
  ('ASESORIA_CONTABLE', 'Asesoría contable',          'Orientación contable personalizada para tomar mejores decisiones.', 'book-open'),
  ('ASESORIA_TRIBUTARIA','Asesoría tributaria',       'Planificación tributaria y cumplimiento de obligaciones con SUNAT.', 'scale'),
  ('GESTION_EMPRESARIAL','Gestión empresarial',       'Constitución, trámites y acompañamiento en la gestión de tu empresa.', 'briefcase'),
  ('OTROS',             'Otros servicios',            'Cuéntanos tu necesidad y diseñamos una solución a medida.', 'more-horizontal')
on conflict (codigo) do nothing;
