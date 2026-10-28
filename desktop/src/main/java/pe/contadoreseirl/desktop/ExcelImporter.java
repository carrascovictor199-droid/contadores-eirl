package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.File;
import java.io.FileInputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

/** Importa clientes desde un Excel (.xlsx) leído con Apache POI. Columnas: documento, razon_social, nombre_comercial, direccion, telefono, correo. */
final class ExcelImporter {
    static final List<String> COLUMNAS = List.of("documento", "razon_social", "nombre_comercial", "direccion", "telefono", "correo");
    private ExcelImporter() {}

    static List<Map<String, String>> leer(File archivo) throws Exception {
        List<Map<String, String>> filas = new ArrayList<>();
        try (XSSFWorkbook wb = new XSSFWorkbook(new FileInputStream(archivo))) {
            Sheet sh = wb.getSheetAt(0); DataFormatter fmt = new DataFormatter();
            Row cab = sh.getRow(0); if (cab == null) return filas;
            Map<Integer, String> idx = new HashMap<>();
            for (int i = 0; i < cab.getLastCellNum(); i++) idx.put(i, Validators.slug(fmt.formatCellValue(cab.getCell(i))).replace('-', '_'));
            for (int r = 1; r <= sh.getLastRowNum(); r++) {
                Row row = sh.getRow(r); if (row == null) continue;
                Map<String, String> m = new LinkedHashMap<>();
                idx.forEach((i, nombre) -> { if (COLUMNAS.contains(nombre)) m.put(nombre, Validators.limpiar(fmt.formatCellValue(row.getCell(i)))); });
                if (m.values().stream().anyMatch(v -> !v.isEmpty())) filas.add(m);
            }
        }
        return filas;
    }

    /** Valida cada fila y registra las válidas en Supabase (RLS aplica). Devuelve un resumen legible. */
    static String importar(Api api, File archivo) throws Exception {
        List<Map<String, String>> filas = leer(archivo);
        int ok = 0, duplicados = 0, invalidos = 0; List<String> detalle = new ArrayList<>();
        for (int i = 0; i < filas.size(); i++) {
            Map<String, String> f = filas.get(i); int n = i + 2;
            String doc = f.getOrDefault("documento", ""), razon = f.getOrDefault("razon_social", "");
            String tel = f.getOrDefault("telefono", ""), correo = f.getOrDefault("correo", "");
            String error = !Validators.documento(doc) ? "documento inválido" : razon.isEmpty() ? "razón social vacía"
                : (!tel.isEmpty() && !Validators.telefono(tel)) ? "teléfono inválido" : (!correo.isEmpty() && !Validators.correo(correo)) ? "correo inválido" : null;
            if (error != null) { invalidos++; if (detalle.size() < 8) detalle.add("Fila " + n + ": " + error); continue; }
            Map<String, Object> body = new HashMap<>();
            body.put("documento", doc); body.put("razon_social", razon); body.put("tipo_cliente", doc.startsWith("20") ? "EMPRESA" : "PERSONA_NATURAL");
            for (String k : List.of("nombre_comercial", "direccion", "telefono", "correo")) body.put(k, f.getOrDefault(k, "").isEmpty() ? null : f.get(k));
            try { JsonNode r = api.restPost("clientes", body); ok++; }
            catch (Exception e) { if (String.valueOf(e.getMessage()).contains("duplicate")) duplicados++; else { invalidos++; if (detalle.size() < 8) detalle.add("Fila " + n + ": " + e.getMessage()); } }
        }
        return "Importación terminada.\nRegistrados: " + ok + "\nYa existían: " + duplicados + "\nCon errores: " + invalidos
            + (detalle.isEmpty() ? "" : "\n\n" + String.join("\n", detalle));
    }
}
