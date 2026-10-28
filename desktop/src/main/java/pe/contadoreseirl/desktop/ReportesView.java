package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import javafx.beans.property.SimpleStringProperty;
import javafx.collections.FXCollections;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class ReportesView {
    private ReportesView() {}
    private static final List<String> TIPOS = List.of("Clientes registrados", "Nuevos clientes (30 días)", "Servicios contratados", "Leads", "Solicitudes", "Actividad mensual");

    static Tab crear(Api api, javafx.stage.Window[] ventana) {
        ComboBox<String> tipo = new ComboBox<>(FXCollections.observableArrayList(TIPOS)); tipo.getSelectionModel().selectFirst();
        DatePicker desde = new DatePicker(), hasta = new DatePicker(); TextField estado = new TextField(); estado.setPromptText("Estado (ej. ACTIVO)");
        TableView<Map<String, String>> tv = new TableView<>(); Label info = new Label();
        final List<Map<String, String>> actuales = new ArrayList<>();
        Button generar = Ui.btnGold("Generar"), csv = Ui.btn("Exportar CSV"), xlsx = Ui.btn("Exportar Excel (.xlsx)");

        generar.setOnAction(e -> {
            String t = tipo.getValue();
            String tabla = switch (t) {
                case "Servicios contratados" -> "cliente_servicio?select=*,clientes(razon_social),servicios(nombre)";
                case "Leads" -> "leads?select=*,servicios(nombre)";
                case "Solicitudes" -> "solicitudes?select=*,clientes(razon_social),servicios(nombre)";
                case "Actividad mensual" -> "actividad?select=created_at,accion";
                default -> "clientes?select=*";
            };
            StringBuilder q = new StringBuilder(tabla).append("&order=created_at.desc");
            LocalDate d0 = desde.getValue(), d1 = hasta.getValue();
            if (d0 == null && t.startsWith("Nuevos")) d0 = LocalDate.now().minusDays(30);
            if (d0 != null) q.append("&created_at=gte.").append(d0);
            if (d1 != null) q.append("&created_at=lt.").append(d1.plusDays(1));
            if (!estado.getText().isBlank() && !t.equals("Actividad mensual")) q.append("&estado=eq.").append(estado.getText().trim().toUpperCase());
            generar.setDisable(true); info.setText("Generando…");
            Ui.async(() -> api.rest(q.toString()), data -> {
                actuales.clear();
                if (t.equals("Actividad mensual")) {
                    Map<String, Integer> porMes = new TreeMap<>();
                    for (JsonNode a : data) porMes.merge(a.get("created_at").asText().substring(0, 7), 1, Integer::sum);
                    porMes.forEach((mes, n) -> { Map<String, String> r = new LinkedHashMap<>(); r.put("mes", mes); r.put("eventos", String.valueOf(n)); actuales.add(r); });
                } else for (JsonNode n : data) actuales.add(Ui.aplanar(n));
                tv.getColumns().clear();
                if (!actuales.isEmpty()) for (String k : actuales.get(0).keySet()) {
                    TableColumn<Map<String, String>, String> c = new TableColumn<>(k); c.setCellValueFactory(x -> new SimpleStringProperty(x.getValue().getOrDefault(k, ""))); c.setPrefWidth(140); tv.getColumns().add(c);
                }
                tv.setItems(FXCollections.observableArrayList(actuales)); info.setText(actuales.size() + " registros"); generar.setDisable(false);
            }, er -> { info.setText(er.getMessage()); generar.setDisable(false); });
        });
        csv.setOnAction(e -> Ui.exportarCsv(ventana[0], Validators.slug(tipo.getValue()), actuales));
        xlsx.setOnAction(e -> ExcelExporter.exportar(ventana[0], Validators.slug(tipo.getValue()), tipo.getValue(), actuales));

        VBox v = new VBox(10, new HBox(8, tipo, new Label("Desde"), desde, new Label("Hasta"), hasta, estado, generar, csv, xlsx), tv, info,
            new Label("El PDF está disponible en la plataforma web (Reportes)."));
        v.setPadding(new Insets(12)); VBox.setVgrow(tv, Priority.ALWAYS); return new Tab("Reportes", v);
    }
}
