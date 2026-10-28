# supabase/config

El CLI de Supabase exige `supabase/config.toml` en la raíz de `supabase/`, por eso
ese archivo vive allí. Esta carpeta documenta los ajustes que se hacen en el
**dashboard** del proyecto remoto (no se versionan por CLI):

| Ajuste (Dashboard) | Valor recomendado |
|---|---|
| Authentication → URL Configuration → Site URL | URL pública del frontend |
| Authentication → URL Configuration → Redirect URLs | `<frontend>/restablecer-contrasena` |
| Authentication → Providers → Email | Habilitado, confirmación de correo activa |
| Authentication → Password | Mínimo 8, mayúsculas, minúsculas y dígitos |
| Authentication → Rate limits | Valores por defecto o más estrictos |
| Storage | El bucket `documentos-clientes` lo crea la migración 009 (privado) |
| Settings → API | Copiar `Project URL` y `anon key` al `.env`; la `service_role key` solo al backend |
