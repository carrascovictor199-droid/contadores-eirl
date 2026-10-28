# Librerías Java utilizadas y dónde

| Librería | Módulo | Uso concreto |
|---|---|---|
| **Google Guava** 33.3 | backend, escritorio | `CharMatcher` (solo dígitos), `Strings.isNullOrEmpty`, `ImmutableSet` (prefijos de RUC válidos), `Preconditions.checkNotNull` — clases `Validaciones.java` (backend) y `Validators.java` (escritorio) |
| **Apache Commons Validator** 1.9 | backend, escritorio | `EmailValidator`: correo con dominio válido (más estricto que `@Email` de Jakarta, que acepta `a@b`) |
| **Apache Commons Lang3** | backend, escritorio | `StringUtils.normalizeSpace` (limpiar nombres), `stripAccents` (nombres de archivo y cabeceras de Excel) |
| **Apache POI** 5.3 (`poi-ooxml`) | escritorio | `ExcelExporter`: reportes `.xlsx` con encabezado navy/dorado. `ExcelImporter`: importación masiva de clientes desde Excel con validación fila por fila |

## Importar clientes desde Excel (escritorio)
Clientes → **Plantilla Excel** (descarga el formato) → llenar → **Importar desde Excel**.
Columnas: `documento, razon_social, nombre_comercial, direccion, telefono, correo`.
Cada fila se valida (DNI/RUC con dígito verificador, correo, teléfono); el resumen indica registrados, ya existentes y filas con error.

La web usa sus propias librerías de JavaScript (SheetJS para Excel y jsPDF para PDF).
