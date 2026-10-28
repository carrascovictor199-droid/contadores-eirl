# Integración SUNAT

El backend expone `GET /api/sunat/ruc/{ruc}` (solo personal). Flujo: RUC → backend → proveedor SUNAT → respuesta → formulario / tabla `consultas_sunat`.

- Estados devueltos: `SUCCESS` (200), `SIN_RESULTADOS` (404), `TIMEOUT` (504), `ERROR` (502).
- Configuración (solo backend): `SUNAT_API_URL`, `SUNAT_API_TOKEN`, `SUNAT_TIMEOUT_MS`.
- Contrato esperado del proveedor: `GET <SUNAT_API_URL>?numero=<ruc>` con `Authorization: Bearer <token>` y respuesta JSON con campos como `razonSocial`, `estado`, `condicion`, `direccion`.
  Si tu proveedor usa otro formato, adapta `SunatService.java` (URL/cabeceras) y el mapeo de campos en `StaffPanel.tsx` (`consultarSunat`) y `ClientesView.java`.
- Cada consulta queda registrada en `consultas_sunat` (auditoría).
