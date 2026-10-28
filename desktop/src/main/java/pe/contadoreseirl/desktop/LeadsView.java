package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class LeadsView {
    private LeadsView() {}

    static Tab crear(Api api) {
        TableView<JsonNode> tv = Ui.tabla(new String[][]{{"Fecha", "created_at"}, {"Nombre", "nombre_completo"}, {"Documento", "documento"}, {"Empresa", "empresa"},
            {"Teléfono", "telefono"}, {"Correo", "correo"}, {"Servicio", "servicios.nombre"}, {"Estado", "estado"}});
        Label estado = new Label();
        Runnable cargar = () -> Ui.async(() -> api.rest("leads?select=*,servicios(nombre)&order=created_at.desc"), d -> { Ui.llenar(tv, d); estado.setText(d.size() + " leads"); }, e -> estado.setText(e.getMessage()));
        Button actualizar = Ui.btn("Actualizar"), cambiar = Ui.btn("Cambiar estado"), convertir = Ui.btnGold("Convertir a cliente");
        actualizar.setOnAction(e -> cargar.run());
        cambiar.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un lead."); return; }
            if ("CONVERTIDO".equals(Ui.t(s, "estado"))) { Ui.info("El lead ya fue convertido."); return; }
            Ui.elegir("Nuevo estado", List.of("NUEVO", "CONTACTADO", "EN_NEGOCIACION", "NO_INTERESADO"), Ui.t(s, "estado")).ifPresent(est ->
                Ui.async(() -> api.patch("leads?id=eq." + Ui.t(s, "id"), Map.of("estado", est)), r -> cargar.run(), er -> Ui.error(er.getMessage()))); });
        convertir.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un lead."); return; }
            if (!Ui.confirmar("¿Convertir a \"" + Ui.t(s, "nombre_completo") + "\" en cliente?")) return;
            Ui.async(() -> api.rpc("convertir_lead_a_cliente", Map.of("p_lead_id", Ui.t(s, "id"))), r -> { Ui.info("Lead convertido a cliente."); cargar.run(); },
                er -> Ui.error("No se pudo convertir (¿tienes permiso de contador/administrador?)")); });
        HBox barra = new HBox(8, actualizar, cambiar); if (api.puedeEscribir()) barra.getChildren().add(convertir);
        cargar.run();
        VBox v = new VBox(10, barra, tv, estado); v.setPadding(new Insets(12)); VBox.setVgrow(tv, Priority.ALWAYS);
        return new Tab("Leads", v);
    }
}
