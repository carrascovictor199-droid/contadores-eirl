package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class ServiciosView {
    private ServiciosView() {}

    static Tab crear(Api api) {
        TableView<JsonNode> cat = Ui.tabla(new String[][]{{"Código", "codigo"}, {"Nombre", "nombre"}, {"Descripción", "descripcion"}, {"Activo", "activo"}});
        TableView<JsonNode> con = Ui.tabla(new String[][]{{"Cliente", "clientes.razon_social"}, {"Servicio", "servicios.nombre"}, {"Estado", "estado"}, {"Inicio", "fecha_inicio"}, {"Fin", "fecha_fin"}});
        Label estado = new Label();
        final JsonNode[] clientes = {null}, servicios = {null};
        Runnable cargar = () -> Ui.async(() -> new JsonNode[]{api.rest("servicios?select=*&order=nombre"),
                api.rest("cliente_servicio?select=*,clientes(razon_social),servicios(nombre)&order=created_at.desc"), api.rest("clientes?select=id,razon_social&estado=eq.ACTIVO&order=razon_social")},
            d -> { servicios[0] = d[0]; clientes[0] = d[2]; Ui.llenar(cat, d[0]); Ui.llenar(con, d[1]); estado.setText(d[0].size() + " servicios · " + d[1].size() + " contratados"); }, e -> estado.setText(e.getMessage()));
        Button actualizar = Ui.btn("Actualizar"); actualizar.setOnAction(e -> cargar.run());
        HBox b1 = new HBox(8, actualizar), b2 = new HBox(8);
        if (api.puedeEscribir()) {
            Button nuevo = Ui.btnGold("Nuevo servicio"), editar = Ui.btn("Editar"), toggle = Ui.btn("Activar/Desactivar");
            nuevo.setOnAction(e -> Ui.formulario("Nuevo servicio", new String[]{"Código (MAYÚSCULAS)", "Nombre", "Descripción"}, new String[]{"", "", ""}).ifPresent(v -> {
                String codigo = v.get(0).toUpperCase().replace(' ', '_');
                if (!codigo.matches("[A-Z0-9_]{2,40}") || v.get(1).isEmpty()) { Ui.error("Código (A-Z, 0-9, _) y nombre son obligatorios."); return; }
                Map<String, Object> body = new HashMap<>(); body.put("codigo", codigo); body.put("nombre", v.get(1)); body.put("descripcion", v.get(2).isEmpty() ? null : v.get(2));
                Ui.async(() -> api.restPost("servicios", body), r -> cargar.run(), er -> Ui.error(er.getMessage().contains("duplicate") ? "Ya existe ese código." : er.getMessage())); }));
            editar.setOnAction(e -> { JsonNode s = cat.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un servicio."); return; }
                Ui.formulario("Editar servicio", new String[]{"Nombre", "Descripción"}, new String[]{Ui.t(s, "nombre"), Ui.t(s, "descripcion")}).ifPresent(v -> {
                    if (v.get(0).isEmpty()) { Ui.error("El nombre es obligatorio."); return; }
                    Map<String, Object> body = new HashMap<>(); body.put("nombre", v.get(0)); body.put("descripcion", v.get(1).isEmpty() ? null : v.get(1));
                    Ui.async(() -> api.patch("servicios?id=eq." + Ui.t(s, "id"), body), r -> cargar.run(), er -> Ui.error(er.getMessage())); }); });
            toggle.setOnAction(e -> { JsonNode s = cat.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un servicio."); return; }
                boolean activo = "true".equals(Ui.t(s, "activo"));
                Ui.async(() -> api.patch("servicios?id=eq." + Ui.t(s, "id"), Map.of("activo", !activo)), r -> cargar.run(), er -> Ui.error(er.getMessage())); });
            b1.getChildren().addAll(nuevo, editar, toggle);

            Button asociar = Ui.btnGold("Asociar servicio a cliente"), estadoBtn = Ui.btn("Cambiar estado");
            asociar.setOnAction(e -> {
                if (clientes[0] == null || servicios[0] == null) return;
                List<String> cs = new java.util.ArrayList<>(), ss = new java.util.ArrayList<>(); Map<String, String> cid = new HashMap<>(), sid = new HashMap<>();
                for (JsonNode c : clientes[0]) { cs.add(Ui.t(c, "razon_social")); cid.put(Ui.t(c, "razon_social"), Ui.t(c, "id")); }
                for (JsonNode s : servicios[0]) if ("true".equals(Ui.t(s, "activo"))) { ss.add(Ui.t(s, "nombre")); sid.put(Ui.t(s, "nombre"), Ui.t(s, "id")); }
                if (cs.isEmpty() || ss.isEmpty()) { Ui.info("Necesitas al menos un cliente activo y un servicio activo."); return; }
                Ui.elegir("Cliente", cs, null).ifPresent(c -> Ui.elegir("Servicio", ss, null).ifPresent(s ->
                    Ui.async(() -> api.restPost("cliente_servicio", Map.of("cliente_id", cid.get(c), "servicio_id", sid.get(s))), r -> cargar.run(),
                        er -> Ui.error("El cliente ya tiene ese servicio vigente o no tienes permiso."))));
            });
            estadoBtn.setOnAction(e -> { JsonNode s = con.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un servicio contratado."); return; }
                Ui.elegir("Estado", List.of("ACTIVO", "PAUSADO", "FINALIZADO", "CANCELADO"), Ui.t(s, "estado")).ifPresent(est ->
                    Ui.async(() -> api.patch("cliente_servicio?id=eq." + Ui.t(s, "id"), Map.of("estado", est)), r -> cargar.run(), er -> Ui.error(er.getMessage()))); });
            b2.getChildren().addAll(asociar, estadoBtn);
        }
        cargar.run();
        VBox v = new VBox(8, new Label("Catálogo de servicios"), b1, cat, new Label("Servicios contratados por clientes"), b2, con, estado);
        v.setPadding(new Insets(12)); VBox.setVgrow(cat, Priority.ALWAYS); VBox.setVgrow(con, Priority.ALWAYS);
        return new Tab("Servicios", v);
    }
}
