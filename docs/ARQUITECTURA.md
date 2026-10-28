# Arquitectura

- **Frontend web**: Supabase SDK con la `anon key`; la seguridad la imponen las políticas RLS.
- **Backend Spring Boot**: valida el JWT de Supabase, usa `service_role` solo en servidor para
  crear usuarios, banearlos, consultar SUNAT y otras operaciones sensibles.
- **JavaFX**: consume únicamente el backend (sin credenciales de base de datos).
- **Persistencia**: exclusivamente Supabase PostgreSQL y Storage.
