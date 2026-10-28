# CONTADORES EIRL — Sistema Integral de Gestión

Plataforma web para clientes + aplicación de escritorio para el personal, sobre **Supabase** (PostgreSQL, Auth, RLS, Storage).

```
Web (React/TS) ──┐
                 ├── Supabase SDK ── RLS ── PostgreSQL
Desktop (JavaFX) ┴── Backend Spring Boot ── Supabase (operaciones sensibles, SUNAT)
```

## Estado

| Módulo | Contenido |
|---|---|
| `supabase/` | Migraciones 001–012, RLS, Storage, Auth, 50 pruebas pgTAP |
| `pagina-web/` | Página pública en un solo archivo (`index.html`): abre con doble clic; envía los leads a Supabase. Cambia `CONFIG` al inicio del script |
| `frontend-web/` | Landing + captación, login/recuperación, panel cliente (resumen, solicitudes, servicios, mensajes, documentos, notificaciones, perfil), panel personal (dashboard con gráficos, clientes con SUNAT, leads→cliente, solicitudes, servicios, mensajes, documentos, reportes CSV/Excel/PDF, usuarios y permisos, configuración) |
| `backend/` | Spring Boot: JWT de Supabase, SUNAT, usuarios/roles, accesos de clientes, validación con Guava + Apache Commons; 17 pruebas |
| `desktop/` | JavaFX: login, dashboard con gráficos, clientes (registrar/editar/SUNAT/acceso), servicios, leads, solicitudes, reportes (CSV y Excel con Apache POI), importación de clientes desde Excel, usuarios, configuración |
| Producción | Dockerfiles, `docker-compose.yml`, CI en GitHub Actions, `docs/PRODUCCION.md` |



## Requisitos

- Cuenta en [Supabase](https://supabase.com) y [Supabase CLI](https://supabase.com/docs/guides/cli)
- Docker (solo para Supabase local), Node 20+, JDK 21, Maven 3.9+

## Base de datos (script para el SQL Editor de Supabase)

La carpeta `base-de-datos/` trae todo en scripts listos para pegar, sin migraciones ni CLI:

1. `1_base_de_datos_completa.sql` → Supabase → SQL Editor → pegar → Run (debe mostrar `tablas_con_rls = 14`).
2. Authentication → Users → Add user (tu correo y contraseña).
3. `2_crear_administrador.sql` → cambiar el correo → Run.
4. `0_reiniciar_base_de_datos.sql` es opcional: borra todo para repetir la instalación.

 copia `.env.example` a `.env` y completa `SUPABASE_URL` y las claves (Settings → API).
Los archivos de `supabase/migrations` son la misma base en formato de migraciones; solo se usan para las pruebas automáticas (CI).

## Crear cuenta (registro de clientes con RUC)

- **Dónde:** botón "Crear cuenta" en `pagina-web/index.html` y en la web React (`/registro`, enlace también en el login).
- **Datos:** RUC/DNI, razón social, nombre comercial, dirección, nombre del titular, teléfono, correo y contraseña.
- **Flujo:** el cliente se registra → confirma su correo → inicia sesión → su portal se activa:
  - Si el estudio ya lo tenía registrado (mismo documento y correo): se **vincula** a su expediente.
  - Si el RUC/DNI **no existe**: se **crea su expediente** con los datos ingresados, marcado *Sin verificar* hasta que el personal pulse **Verificar**.
  - Si el documento ya existe con otro correo: queda una **solicitud pendiente** para validar su identidad (nadie accede a datos ajenos).
- **Seguridad:** toda cuenta nueva es CLIENTE (nunca personal); correo confirmado obligatorio; el cliente no puede verificarse solo. El personal lo crea un administrador desde Usuarios.
- **Supabase:** Authentication → Providers → Email → "Confirm email" activado, y Redirect URLs con `<tu-app>/login`.

## Página web pública (sin instalar nada)

`pagina-web/index.html` es la web pública completa (inicio, servicios, beneficios, contacto). Edita el bloque `CONFIG`
(URL y anon key de Supabase, y `APP_URL` de la plataforma) y ábrela con doble clic o súbela a cualquier hosting.
El formulario guarda el lead en Supabase con estado NUEVO. La plataforma de clientes y personal está en `frontend-web/`.

## Ejecución rápida (orden)

1. **Supabase**: crea el proyecto y ejecuta los scripts de `base-de-datos/` (pasos arriba).
2. **`.env`**: copia `.env.example` a `.env` (raíz) y completa URL, anon key, service_role key y, si la tienes, la API SUNAT.
3. **Frontend**: `cd frontend-web && npm install && npm run dev` → http://localhost:5173
4. **Backend**: `scripts/start-backend.ps1` (Windows) o `scripts/start-backend.sh` → http://localhost:8080/api/health
5. **Escritorio**: `scripts/start-desktop.ps1` o `scripts/start-desktop.sh`
6. **Docker (opcional)**: `docker compose --env-file .env up --build`

Flujo de prueba: formulario público → lead en Supabase → login del administrador → Leads → Convertir → Clientes.
Para que un cliente use su portal: Clientes → **Acceso** (web o escritorio). El backend crea el usuario en Supabase Auth con rol CLIENTE y lo vincula al cliente.

**SUNAT**: define `SUNAT_API_URL` y `SUNAT_API_TOKEN` (proveedor con `GET ?numero=<ruc>` y Bearer token). Sin ellos el módulo responde "no configurado".
**Testimonios**: la web no inventa datos; agrega los reales en `frontend-web/src/pages/Home.tsx` (`TESTIMONIOS`).
**Auth/JWT**: el backend valida con las claves JWKS de Supabase (proyectos con claves de firma asimétricas, el estándar actual).

## Migraciones

| Archivo | Contenido |
|---|---|
| 001_initial_schema | Enums, `set_updated_at`, validación de RUC/DNI |
| 002_roles | `roles`, `profiles`, `user_roles`, helpers de rol, alta automática de perfil |
| 003_clients | `clientes`, `empresas`, protección de campos |
| 004_services | `servicios`, `cliente_servicio` |
| 005_leads | `leads`, `convertir_lead_a_cliente()` (atómica, sin duplicados) |
| 006_solicitudes | `solicitudes`, `mensajes`, `notificaciones`, `actividad` + triggers |
| 007_sunat_documentos | `consultas_sunat`, `documentos` |
| 008_rls | Políticas RLS de todas las tablas |
| 009_storage | Bucket privado `documentos-clientes` + políticas |
| 010_catalogo_servicios | Los 6 servicios base |
| 011_profiles_correo | Correo en `profiles` para listar usuarios |
| 012_autoregistro | Registro de cuentas con RUC: `vincular_mi_cuenta()`, expediente autocreado (sin verificar), activación del portal al convertir leads |

## Seguridad (decisiones clave)

- Todo usuario nuevo nace como **CLIENTE**; el rol nunca se lee de metadatos del usuario.
- Solo ADMINISTRADOR asigna roles y activa/desactiva usuarios.
- Visitantes anónimos solo pueden **leer servicios activos** y **crear leads en estado NUEVO**.
  Con supabase-js, inserta el lead sin `.select()` (no hay política de lectura para anon).
- Clientes solo ven y crean lo suyo; no pueden cambiar su documento, estado ni roles.
- Al desactivar un usuario, el backend debe además **banearlo en Auth** (`ban_duration`).
- Considera activar CAPTCHA en Auth y un límite de tasa en el formulario público de leads.

## Permisos por rol

| Recurso | ADMIN | CONTADOR | ASISTENTE | CLIENTE |
|---|---|---|---|---|
| Clientes | todo | crear/editar | ver | solo el suyo (contacto) |
| Servicios / contratados | todo | todo | ver | los suyos |
| Leads | todo | gestionar + convertir | ver/cambiar estado | — |
| Solicitudes | todo | responder | ver | crear/cancelar las suyas |
| Mensajes | todo | enviar/ver | enviar/ver | los suyos |
| Actividad / reportes | sí | sí | — | — |
| Usuarios y roles | sí | — | — | — |


## Documentación adicional

`docs/LIBRERIAS.md` (Guava, Apache Commons, Apache POI) · `docs/ARQUITECTURA.md` · `docs/SUNAT.md` · `docs/TESTING.md` · `docs/PRODUCCION.md`
