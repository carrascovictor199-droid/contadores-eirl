package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.File;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class ClientesView {
    private ClientesView() {}

    static Tab crear(Api api) {
        TableView<JsonNode> tv = Ui.tabla(new String[][]{{"Documento", "documento"}, {"Razón social", "razon_social"}, {"Nombre comercial", "nombre_comercial"},
            {"Tipo", "tipo_cliente"}, {"Teléfono", "telefono"}, {"Correo", "correo"}, {"Estado", "estado"}, {"Verificado", "verificado"}, {"Acceso portal", "user_id"}});
        Label estado = new Label(); TextField buscar = new TextField(); buscar.setPromptText("Buscar por documento, razón social o correo…");
        final JsonNode[] datos = {null};
        Runnable pintar = () -> {
            if (datos[0] == null) return; String q = buscar.getText().toLowerCase();
            var filtrado = com.fasterxml.jackson.databind.node.JsonNodeFactory.instance.arrayNode();
            for (JsonNode c : datos[0]) if ((Ui.t(c, "documento") + " " + Ui.t(c, "razon_social") + " " + Ui.t(c, "correo")).toLowerCase().contains(q)) filtrado.add(c);
            Ui.llenar(tv, filtrado); estado.setText(filtrado.size() + " clientes");
        };
        Runnable cargar = () -> Ui.async(() -> api.rest("clientes?select=*&order=created_at.desc"), d -> { datos[0] = d; pintar.run(); }, e -> estado.setText(e.getMessage()));
        buscar.textProperty().addListener((o, a, b) -> pintar.run());

        Button actualizar = Ui.btn("Actualizar"); actualizar.setOnAction(e -> cargar.run());
        HBox barra = new HBox(8, actualizar);
        if (api.puedeEscribir()) {
            Button nuevo = Ui.btnGold("Registrar cliente"), editar = Ui.btn("Editar"), toggle = Ui.btn("Activar/Desactivar"), acceso = Ui.btn("Crear acceso al portal");
            nuevo.setOnAction(e -> formulario(api, null, cargar));
            editar.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) Ui.info("Selecciona un cliente."); else formulario(api, s, cargar); });
            toggle.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un cliente."); return; }
                String nuevoEstado = "ACTIVO".equals(Ui.t(s, "estado")) ? "INACTIVO" : "ACTIVO";
                Ui.async(() -> api.patch("clientes?id=eq." + Ui.t(s, "id"), Map.of("estado", nuevoEstado)), r -> cargar.run(), er -> Ui.error(er.getMessage())); });
            acceso.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un cliente."); return; }
                if (!Ui.t(s, "user_id").isEmpty()) { Ui.info("Este cliente ya tiene acceso."); return; }
                Ui.formulario("Acceso al portal", new String[]{"Correo", "Contraseña inicial"}, new String[]{Ui.t(s, "correo"), ""}).ifPresent(v -> {
                    if (!Validators.correo(v.get(0))) { Ui.error("Correo no válido."); return; }
                    if (!Validators.clave(v.get(1))) { Ui.error("Contraseña: mínimo 8, con mayúscula, minúscula y número."); return; }
                    Ui.async(() -> api.backendPost("/clientes/" + Ui.t(s, "id") + "/acceso", Map.of("correo", v.get(0), "password", v.get(1))),
                        r -> { Ui.info("Acceso creado."); cargar.run(); }, er -> Ui.error(er.getMessage())); }); });
            Button verificar = Ui.btn("Marcar verificado");
            verificar.setOnAction(e -> { JsonNode s = tv.getSelectionModel().getSelectedItem(); if (s == null) { Ui.info("Selecciona un cliente."); return; }
                if (!"false".equals(Ui.t(s, "verificado"))) { Ui.info("Este cliente ya está verificado."); return; }
                Ui.async(() -> api.patch("clientes?id=eq." + Ui.t(s, "id"), Map.of("verificado", true)), r -> cargar.run(), er -> Ui.error(er.getMessage())); });
            Button importar = Ui.btn("Importar desde Excel"), plantilla = Ui.btn("Plantilla Excel");
            importar.setOnAction(e -> {
                javafx.stage.FileChooser fc = new javafx.stage.FileChooser();
                fc.getExtensionFilters().add(new javafx.stage.FileChooser.ExtensionFilter("Excel (*.xlsx)", "*.xlsx"));
                File f = fc.showOpenDialog(importar.getScene().getWindow()); if (f == null) return;
                Ui.async(() -> ExcelImporter.importar(api, f), r -> { Ui.info(r); cargar.run(); }, er -> Ui.error("No se pudo leer el archivo: " + er.getMessage()));
            });
            plantilla.setOnAction(e -> { Map<String, String> fila = new LinkedHashMap<>(); for (String c : ExcelImporter.COLUMNAS) fila.put(c, "");
                ExcelExporter.exportar(plantilla.getScene().getWindow(), "plantilla-clientes", "Clientes", List.of(fila)); });
            barra.getChildren().addAll(nuevo, editar, toggle, verificar, acceso, importar, plantilla);
        }
        cargar.run();
        VBox v = new VBox(10, barra, buscar, tv, estado); v.setPadding(new Insets(12)); VBox.setVgrow(tv, Priority.ALWAYS);
        return new Tab("Clientes", v);
    }

    /** Crear (existente == null) o editar un cliente, con consulta SUNAT integrada. */
    private static void formulario(Api api, JsonNode existente, Runnable recargar) {
        boolean edicion = existente != null;
        Dialog<ButtonType> d = new Dialog<>(); d.setTitle(edicion ? "Editar cliente" : "Registrar cliente");
        d.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);
        TextField doc = new TextField(), razon = new TextField(), comercial = new TextField(), dir = new TextField(), tel = new TextField(), correo = new TextField();
        if (edicion) { doc.setText(Ui.t(existente, "documento")); doc.setDisable(true); razon.setText(Ui.t(existente, "razon_social")); comercial.setText(Ui.t(existente, "nombre_comercial"));
            dir.setText(Ui.t(existente, "direccion")); tel.setText(Ui.t(existente, "telefono")); correo.setText(Ui.t(existente, "correo")); }
        Button sunat = Ui.btnGold("Consultar SUNAT"); sunat.setDisable(edicion); Label st = new Label();
        sunat.setOnAction(e -> {
            if (!Validators.ruc(doc.getText().trim())) { st.setText("Ingresa un RUC válido de 11 dígitos."); return; }
            sunat.setDisable(true); st.setText("Consultando…");
            Ui.async(() -> api.sunat(doc.getText().trim()), r -> {
                JsonNode x = r.path("data");
                String rs = firstNonEmpty(x, "razonSocial", "nombre_o_razon_social", "razon_social"); if (!rs.isEmpty()) razon.setText(rs);
                String di = firstNonEmpty(x, "direccion"); if (!di.isEmpty()) dir.setText(di);
                st.setText("SUNAT: estado " + x.path("estado").asText("—") + " · condición " + x.path("condicion").asText("—")); sunat.setDisable(false);
            }, er -> { st.setText(er.getMessage()); sunat.setDisable(false); });
        });
        GridPane g = new GridPane(); g.setHgap(8); g.setVgap(8); g.setPadding(new Insets(14));
        String[] ls = {"DNI / RUC *", "Razón social *", "Nombre comercial", "Dirección", "Teléfono", "Correo"}; TextField[] fs = {doc, razon, comercial, dir, tel, correo};
        for (int i = 0; i < ls.length; i++) { fs[i].setPrefWidth(300); g.add(new Label(ls[i]), 0, i); g.add(fs[i], 1, i); }
        g.add(sunat, 2, 0); g.add(st, 1, ls.length);
        d.getDialogPane().setContent(g);
        d.getDialogPane().lookupButton(ButtonType.OK).addEventFilter(javafx.event.ActionEvent.ACTION, ev -> {
            String err = null;
            if (!Validators.documento(doc.getText().trim())) err = "DNI (8 dígitos) o RUC válido requerido.";
            else if (razon.getText().isBlank()) err = "La razón social es obligatoria.";
            else if (!tel.getText().isBlank() && !Validators.telefono(tel.getText().trim())) err = "Teléfono no válido.";
            else if (!correo.getText().isBlank() && !Validators.correo(correo.getText().trim())) err = "Correo no válido.";
            if (err != null) { Ui.error(err); ev.consume(); }
        });
        d.showAndWait().filter(b -> b == ButtonType.OK).ifPresent(b -> {
            Map<String, Object> datos = new HashMap<>();
            datos.put("razon_social", razon.getText().trim()); datos.put("nombre_comercial", nul(comercial)); datos.put("direccion", nul(dir)); datos.put("telefono", nul(tel)); datos.put("correo", nul(correo));
            Ui.async(() -> {
                if (edicion) return api.patch("clientes?id=eq." + Ui.t(existente, "id"), datos);
                datos.put("documento", doc.getText().trim()); datos.put("tipo_cliente", doc.getText().startsWith("20") ? "EMPRESA" : "PERSONA_NATURAL");
                return api.restPost("clientes", datos);
            }, r -> recargar.run(), er -> Ui.error(er.getMessage().contains("duplicate") ? "Ya existe un cliente con ese documento." : er.getMessage()));
        });
    }

    private static Object nul(TextField f) { return f.getText().isBlank() ? null : f.getText().trim(); }
    private static String firstNonEmpty(JsonNode n, String... keys) { for (String k : keys) if (n.hasNonNull(k)) return n.get(k).asText(); return ""; }
}
