package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class SunatView {
    private SunatView() {}

    static Tab crear(Api api) {
        TextField ruc = new TextField(); ruc.setPromptText("RUC (11 dígitos)"); ruc.setPrefWidth(220);
        Button consultar = Ui.btnGold("Consultar SUNAT"); Label estado = new Label(); GridPane res = new GridPane(); res.setHgap(12); res.setVgap(6);
        consultar.setOnAction(e -> {
            res.getChildren().clear();
            if (!Validators.ruc(ruc.getText().trim())) { estado.setText("RUC inválido (11 dígitos, dígito verificador incorrecto)."); return; }
            consultar.setDisable(true); estado.setText("Consultando…");
            Ui.async(() -> api.sunat(ruc.getText().trim()), r -> {
                JsonNode d = r.path("data"); estado.setText("Consulta exitosa");
                String[][] filas = {{"RUC", ruc.getText().trim()}, {"Razón social", pick(d, "razonSocial", "nombre_o_razon_social", "razon_social")},
                    {"Estado", pick(d, "estado")}, {"Condición", pick(d, "condicion")}, {"Dirección", pick(d, "direccion")}};
                for (int i = 0; i < filas.length; i++) { Label k = new Label(filas[i][0] + ":"); k.setStyle("-fx-font-weight: bold;"); res.add(k, 0, i); res.add(new Label(filas[i][1]), 1, i); }
                consultar.setDisable(false);
            }, er -> { estado.setText(er.getMessage().isBlank() ? "Sin resultados" : er.getMessage()); consultar.setDisable(false); });
        });
        VBox v = new VBox(12, new HBox(8, ruc, consultar), estado, res,
            new Label("Para guardar los datos en un cliente usa Clientes → Registrar cliente → Consultar SUNAT."));
        v.setPadding(new Insets(16)); return new Tab("SUNAT", v);
    }
    private static String pick(JsonNode n, String... keys) { for (String k : keys) if (n.hasNonNull(k)) return n.get(k).asText(); return "—"; }
}
