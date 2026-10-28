# Pruebas

| Capa | Comando | Qué cubre |
|---|---|---|
| Base de datos | `supabase test db` | RLS por rol, aislamiento entre clientes, conversión de leads sin duplicados, registro de cuentas con RUC y vinculación segura, registro y vinculación segura de cuentas, validación de RUC, protección de campos, notificaciones |
| Backend | `cd backend && mvn verify` | 401/403 por rol, validación de datos (Guava + Commons), no auto-desactivación del admin, SUNAT sin configurar |
| Frontend | `cd frontend-web && npm test` | Validadores (DNI/RUC/correo/teléfono) y exportación CSV |
| Todo | GitHub Actions (`.github/workflows/ci.yml`) | Ejecuta las tres capas |

Prueba clave solicitada: **un cliente no puede acceder a datos de otro cliente** → `supabase/tests/database/rls.test.sql` y `negocio.test.sql`.
