# Puesta en producción

## 1. Supabase
1. Proyecto en una región cercana (p. ej. São Paulo). Plan Pro recomendado (backups diarios y sin pausa).
2. Ejecutar `base-de-datos/1_base_de_datos_completa.sql` en el SQL Editor (ver `base-de-datos/LEEME.txt`).
3. Crear el primer administrador (`supabase/seed/bootstrap_admin.sql`).
4. Authentication → URL Configuration: Site URL = dominio público; Redirect URLs = `<dominio>/restablecer-contrasena` y `<dominio>/login` (confirmación de correo del registro).
5. Authentication → Providers → Email: confirmación activa. Configurar un SMTP propio (el de pruebas tiene límites).
6. Activar CAPTCHA (Turnstile/hCaptcha) en Auth y un límite de tasa para el formulario público de leads.
7. Verificar en Table Editor que **todas** las tablas muestran RLS habilitado.

## 2. Backend
- Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BACKEND_ALLOWED_ORIGINS` (dominio del frontend), `SUNAT_API_URL`, `SUNAT_API_TOKEN`.
- Desplegar la imagen `backend/Dockerfile` (Render, Railway, Fly.io, VPS…) detrás de HTTPS.
- La `service_role key` solo se configura como secreto del servidor.

## 3. Frontend
- Build: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_BASE_URL=https://api.tu-dominio/api`.
- `frontend-web/Dockerfile` (nginx) o cualquier hosting estático (Netlify, Vercel, Cloudflare Pages) con fallback SPA a `index.html`.

## 4. Escritorio
- Definir `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `DESKTOP_API_BASE_URL` en cada equipo. Sin secretos.
- Empaquetado nativo (opcional): `jpackage` sobre el JAR generado con `mvn package`.

## 5. Checklist
- [ ] HTTPS en frontend y backend
- [ ] `.env` fuera del repositorio y secretos rotados si se expusieron
- [ ] `supabase test db` y `mvn verify` en verde
- [ ] Backups de Supabase habilitados
- [ ] Usuario administrador con contraseña robusta
