package pe.contadoreseirl.desktop;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import javafx.stage.FileChooser;
import javafx.stage.Window;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.util.WorkbookUtil;
import org.apache.poi.xssf.usermodel.XSSFCellStyle;
import org.apache.poi.xssf.usermodel.XSSFColor;
import org.apache.poi.xssf.usermodel.XSSFFont;
import org.apache.poi.xssf.usermodel.XSSFSheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

/** Exporta reportes a Excel (.xlsx) con Apache POI, con el encabezado corporativo (navy/dorado). */
final class ExcelExporter {
    private ExcelExporter() {}

    static void exportar(Window ventana, String nombreArchivo, String hoja, List<Map<String, String>> filas) {
        if (filas.isEmpty()) { Ui.info("No hay datos para exportar."); return; }
        FileChooser fc = new FileChooser(); fc.setInitialFileName(nombreArchivo + ".xlsx");
        fc.getExtensionFilters().add(new FileChooser.ExtensionFilter("Excel (*.xlsx)", "*.xlsx"));
        File destino = fc.showSaveDialog(ventana); if (destino == null) return;
        try (XSSFWorkbook wb = new XSSFWorkbook(); OutputStream os = new FileOutputStream(destino)) {
            XSSFSheet sh = wb.createSheet(WorkbookUtil.createSafeSheetName(hoja));
            XSSFCellStyle cab = wb.createCellStyle();
            cab.setFillForegroundColor(new XSSFColor(new byte[]{(byte) 0x1B, (byte) 0x3A, (byte) 0x6B}, null));
            cab.setFillPattern(FillPatternType.SOLID_FOREGROUND);
            XSSFFont f = wb.createFont(); f.setBold(true); f.setColor(new XSSFColor(new byte[]{(byte) 0xC8, (byte) 0xA8, (byte) 0x4B}, null)); cab.setFont(f);

            List<String> cols = new ArrayList<>(filas.get(0).keySet());
            Row h = sh.createRow(0);
            for (int i = 0; i < cols.size(); i++) { Cell c = h.createCell(i); c.setCellValue(cols.get(i)); c.setCellStyle(cab); }
            for (int r = 0; r < filas.size(); r++) {
                Row row = sh.createRow(r + 1);
                for (int i = 0; i < cols.size(); i++) row.createCell(i).setCellValue(filas.get(r).getOrDefault(cols.get(i), ""));
            }
            sh.createFreezePane(0, 1);
            for (int i = 0; i < cols.size(); i++) { try { sh.autoSizeColumn(i); } catch (Throwable ignorado) { sh.setColumnWidth(i, 20 * 256); } }
            wb.write(os);
            Ui.info("Excel guardado: " + destino.getName());
        } catch (Exception e) { Ui.error("No se pudo guardar el Excel: " + e.getMessage()); }
    }
}
