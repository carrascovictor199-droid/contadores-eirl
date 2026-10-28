package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class SolicitudesView {
    private SolicitudesView() {}

    static Tab crear(Api api) {
        TableView<JsonNode> tv = Ui.tabla(new String[][]{{"Fecha", "created_at"}, {"Cliente", "clientes.razon_social"}, {"Asunto", "asunto"}, {"Servicio", "servicios.nombre"}, {"Estado", "estado"}, {"Respuesta", "respuesta"}});
        TextArea detalle = new TextArea(); detalle.setEditable(false); detalle.setPrefRowCount(4);
        tv.getSelectionModel().selectedItemProperty().addListener((o, a, s) -> detalle.setText(s == null ? "" : Ui.t(s, "descripcion")));
        Label estado = new Label();
        Runnable cargar = () -> Ui.async(() -> api.rest("solicitudes?select=*,clientes(razon_social),servicios(nombre)&order=created_at.desc"), d -> { Ui.llenar(tv, d); estado.setText(d.size() + " solicitudes"); }, e -> estado.setText(e.getMessage()));
        Button actualizar = Ui.btn("Actualizar"); actualizar.setOnAction(e -> cargar.run());
        HBox barra = new HBox(8, actualizar);
        if (api.puedeEscribir()) {
            Button responder = Ui.btnGold("Responder / cambiar estado");
            responder.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona una solicitud."); return; }
                Ui.formulario("Responder solicitud", new String[]{"Respuesta"}, new String[]{Ui.t(s, "respuesta")}).ifPresent(v ->
                    Ui.elegir("Estado de la solicitud", List.of("PENDIENTE", "EN_REVISION", "ATENDIDA", "CANCELADA"), Ui.t(s, "estado")).ifPresent(est -> {
                        Map<String, Object> body = new HashMap<>(); body.put("estado", est); body.put("respuesta", v.get(0).isEmpty() ? null : v.get(0));
                        Ui.async(() -> api.patch("solicitudes?id=eq." + Ui.t(s, "id"), body), r -> cargar.run(), er -> Ui.error(er.getMessage())); })); });
            barra.getChildren().add(responder);
        }
        cargar.run();
        VBox v = new VBox(10, barra, tv, new Label("Descripción del cliente:"), detalle, estado); v.setPadding(new Insets(12)); VBox.setVgrow(tv, Priority.ALWAYS);
        return new Tab("Solicitudes", v);
    }
}
