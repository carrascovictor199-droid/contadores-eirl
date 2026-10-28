package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import javafx.geometry.Insets;
import javafx.scene.chart.BarChart;
import javafx.scene.chart.CategoryAxis;
import javafx.scene.chart.NumberAxis;
import javafx.scene.chart.XYChart;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.Tab;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;

final class DashboardView {
    private DashboardView() {}

    static Tab crear(Api api) {
        Label kpis = new Label("Cargando…"); kpis.setStyle("-fx-font-size: 16px;");
        BarChart<String, Number> leads = grafico("Leads por estado"), sols = grafico("Solicitudes por estado");
        Button recargar = Ui.btn("Actualizar");
        Runnable cargar = () -> Ui.async(() -> new JsonNode[]{
                api.rest("clientes?select=id,created_at"), api.rest("leads?select=estado"),
                api.rest("solicitudes?select=estado"), api.rest("cliente_servicio?select=id&estado=eq.ACTIVO")},
            d -> {
                String hace30 = java.time.Instant.now().minus(java.time.Duration.ofDays(30)).toString();
                long nuevos = 0; for (JsonNode c : d[0]) if (c.get("created_at").asText().compareTo(hace30) >= 0) nuevos++;
                long leadsNuevos = count(d[1], "NUEVO"), pend = count(d[2], "PENDIENTE");
                kpis.setText("Total clientes: " + d[0].size() + "     Clientes nuevos (30 d): " + nuevos
                    + "\nSolicitudes pendientes: " + pend + "     Servicios activos: " + d[3].size() + "     Leads nuevos: " + leadsNuevos);
                poblar(leads, d[1], "NUEVO", "CONTACTADO", "EN_NEGOCIACION", "CONVERTIDO", "NO_INTERESADO");
                poblar(sols, d[2], "PENDIENTE", "EN_REVISION", "ATENDIDA", "CANCELADA");
            }, e -> kpis.setText(e.getMessage()));
        recargar.setOnAction(e -> cargar.run()); cargar.run();
        VBox v = new VBox(14, kpis, new HBox(12, leads, sols), recargar); v.setPadding(new Insets(16));
        return new Tab("Dashboard", v);
    }

    private static long count(JsonNode arr, String estado) { long n = 0; for (JsonNode r : arr) if (estado.equals(r.get("estado").asText())) n++; return n; }

    private static BarChart<String, Number> grafico(String titulo) {
        BarChart<String, Number> c = new BarChart<>(new CategoryAxis(), new NumberAxis());
        c.setTitle(titulo); c.setLegendVisible(false); c.setPrefSize(480, 300); c.setAnimated(false); return c;
    }
    private static void poblar(BarChart<String, Number> c, JsonNode rows, String... estados) {
        XYChart.Series<String, Number> s = new XYChart.Series<>();
        for (String e : estados) s.getData().add(new XYChart.Data<>(e, count(rows, e)));
        c.getData().setAll(s);
    }
}
