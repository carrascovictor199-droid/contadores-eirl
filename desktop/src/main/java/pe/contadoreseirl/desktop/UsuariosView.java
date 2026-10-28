package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

/** Solo ADMINISTRADOR. Las operaciones de identidad pasan por el backend (service_role en servidor). */
final class UsuariosView {
    private UsuariosView() {}
    private static final List<String> ROLES = List.of("ADMINISTRADOR", "CONTADOR", "ASISTENTE", "CLIENTE");

    static Tab crear(Api api) {
        TableView<JsonNode> tv = Ui.tabla(new String[][]{{"Nombre", "nombre_completo"}, {"Correo", "correo"}, {"Rol", "user_roles.0.roles.codigo"}, {"Activo", "activo"}});
        // La ruta con índice no la resuelve Ui.t; se muestra el rol con una columna calculada.
        tv.getColumns().remove(2);
        TableColumn<JsonNode, String> rol = new TableColumn<>("Rol");
        rol.setCellValueFactory(d -> new javafx.beans.property.SimpleStringProperty(rolDe(d.getValue()))); tv.getColumns().add(2, rol);
        Label estado = new Label();
        Runnable cargar = () -> Ui.async(() -> api.rest("profiles?select=id,nombre_completo,correo,activo,user_roles(roles(codigo))&order=created_at.desc"),
            d -> { Ui.llenar(tv, d); estado.setText(d.size() + " usuarios"); }, e -> estado.setText(e.getMessage()));
        Button actualizar = Ui.btn("Actualizar"), nuevo = Ui.btnGold("Crear usuario"), cambiarRol = Ui.btn("Cambiar rol"), toggle = Ui.btn("Activar/Desactivar");
        actualizar.setOnAction(e -> cargar.run());
        nuevo.setOnAction(e -> Ui.formulario("Crear usuario", new String[]{"Nombre completo", "Correo", "Contraseña inicial"}, new String[]{"", "", ""}).ifPresent(v ->
            Ui.elegir("Rol", ROLES, "CONTADOR").ifPresent(r -> {
                if (v.get(0).isEmpty() || !Validators.correo(v.get(1))) { Ui.error("Nombre y correo válidos son obligatorios."); return; }
                if (!Validators.clave(v.get(2))) { Ui.error("Contraseña: mínimo 8, con mayúscula, minúscula y número."); return; }
                Ui.async(() -> api.backendPost("/admin/users", Map.of("nombreCompleto", v.get(0), "correo", v.get(1), "password", v.get(2), "rol", r)),
                    x -> { Ui.info("Usuario creado."); cargar.run(); }, er -> Ui.error(er.getMessage())); })));
        cambiarRol.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un usuario."); return; }
            Ui.elegir("Nuevo rol", ROLES, rolDe(s)).ifPresent(r -> Ui.async(() -> api.backendPatch("/admin/users/" + Ui.t(s, "id") + "/rol", Map.of("rol", r)),
                x -> cargar.run(), er -> Ui.error(er.getMessage()))); });
        toggle.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un usuario."); return; }
            boolean activo = "true".equals(Ui.t(s, "activo"));
            Ui.async(() -> api.backendPatch("/admin/users/" + Ui.t(s, "id") + "/activo", Map.of("activo", !activo)), x -> cargar.run(), er -> Ui.error(er.getMessage())); });
        cargar.run();
        VBox v = new VBox(10, new HBox(8, actualizar, nuevo, cambiarRol, toggle), tv, estado); v.setPadding(new Insets(12)); VBox.setVgrow(tv, Priority.ALWAYS);
        return new Tab("Usuarios", v);
    }
    private static String rolDe(JsonNode u) { JsonNode r = u.path("user_roles"); return r.isArray() && r.size() > 0 ? r.get(0).path("roles").path("codigo").asText("—") : "—"; }
}
