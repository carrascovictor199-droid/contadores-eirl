package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Consumer;
import javafx.application.Platform;
import javafx.collections.FXCollections;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.GridPane;
import javafx.stage.FileChooser;
import javafx.stage.Window;

/** Utilidades de interfaz compartidas. */
final class Ui {
    static final String NAVY = "#1B3A6B", GOLD = "#C8A84B";
    private Ui() {}

    interface Tarea<T> { T run() throws Exception; }

    static Button btn(String texto) {
        Button b = new Button(texto);
        b.setStyle("-fx-background-color: " + NAVY + "; -fx-text-fill: white; -fx-background-radius: 6;");
        return b;
    }
    static Button btnGold(String texto) {
        Button b = new Button(texto);
        b.setStyle("-fx-background-color: " + GOLD + "; -fx-text-fill: " + NAVY + "; -fx-background-radius: 6;");
        return b;
    }

    /** Ejecuta en segundo plano y devuelve el resultado al hilo de JavaFX. */
    static <T> void async(Tarea<T> tarea, Consumer<T> ok, Consumer<Throwable> err) {
        Thread th = new Thread(() -> {
            try { T r = tarea.run(); Platform.runLater(() -> ok.accept(r)); }
            catch (Throwable ex) { Platform.runLater(() -> err.accept(ex)); }
        });
        th.setDaemon(true); th.start();
    }

    static String t(JsonNode n, String dotted) {
        JsonNode c = n;
        for (String k : dotted.split("\\.")) { if (c == null || c.isMissingNode() || c.isNull()) return ""; c = c.get(k); }
        return c == null || c.isNull() ? "" : c.asText();
    }

    static void info(String msg) { new Alert(Alert.AlertType.INFORMATION, msg).showAndWait(); }
    static void error(String msg) { new Alert(Alert.AlertType.ERROR, msg).showAndWait(); }
    static boolean confirmar(String msg) { return new Alert(Alert.AlertType.CONFIRMATION, msg).showAndWait().filter(b -> b == ButtonType.OK).isPresent(); }

    /** Tabla de JsonNode. cols = {{"Encabezado", "clave.anidada"}, ...} */
    static TableView<JsonNode> tabla(String[][] cols) {
        TableView<JsonNode> tv = new TableView<>();
        for (String[] c : cols) {
            TableColumn<JsonNode, String> col = new TableColumn<>(c[0]);
            col.setCellValueFactory(d -> new javafx.beans.property.SimpleStringProperty(t(d.getValue(), c[1])));
            col.setPrefWidth(160); tv.getColumns().add(col);
        }
        tv.setColumnResizePolicy(TableView.CONSTRAINED_RESIZE_POLICY_FLEX_LAST_COLUMN);
        return tv;
    }
    static void llenar(TableView<JsonNode> tv, JsonNode arr) {
        var rows = FXCollections.<JsonNode>observableArrayList(); arr.forEach(rows::add); tv.setItems(rows);
    }

    /** Diálogo de texto con varios campos. Un label con "Contraseña" se muestra como password. */
    static Optional<List<String>> formulario(String titulo, String[] labels, String[] valores) {
        Dialog<ButtonType> d = new Dialog<>(); d.setTitle(titulo);
        d.getDialogPane().getButtonTypes().addAll(ButtonType.OK, ButtonType.CANCEL);
        GridPane g = new GridPane(); g.setHgap(8); g.setVgap(8); g.setPadding(new Insets(14));
        List<TextInputControl> campos = new ArrayList<>();
        for (int i = 0; i < labels.length; i++) {
            TextInputControl tf = labels[i].contains("Contraseña") ? new PasswordField() : new TextField(valores != null ? valores[i] : "");
            tf.setPrefWidth(280); campos.add(tf); g.add(new Label(labels[i]), 0, i); g.add(tf, 1, i);
        }
        d.getDialogPane().setContent(g);
        return d.showAndWait().filter(b -> b == ButtonType.OK).map(b -> campos.stream().map(c -> c.getText().trim()).toList());
    }

    static Optional<String> elegir(String titulo, List<String> opciones, String actual) {
        ChoiceDialog<String> d = new ChoiceDialog<>(actual != null ? actual : opciones.get(0), opciones);
        d.setTitle(titulo); d.setHeaderText(titulo); return d.showAndWait();
    }

    /** Aplana un JsonNode a columnas simples (los objetos anidados pasan a "padre.hijo"). */
    static Map<String, String> aplanar(JsonNode n) {
        Map<String, String> m = new LinkedHashMap<>();
        n.fields().forEachRemaining(e -> {
            if (e.getValue().isObject()) e.getValue().fields().forEachRemaining(x -> m.put(e.getKey() + "." + x.getKey(), x.getValue().asText("")));
            else if (!e.getValue().isArray()) m.put(e.getKey(), e.getValue().isNull() ? "" : e.getValue().asText());
        });
        return m;
    }

    /** Exporta filas a CSV (UTF-8 con BOM; Excel lo abre directamente). */
    static void exportarCsv(Window w, String nombre, List<Map<String, String>> filas) {
        if (filas.isEmpty()) { info("No hay datos para exportar."); return; }
        FileChooser fc = new FileChooser(); fc.setInitialFileName(nombre + ".csv");
        fc.getExtensionFilters().add(new FileChooser.ExtensionFilter("CSV", "*.csv"));
        File f = fc.showSaveDialog(w); if (f == null) return;
        try (PrintWriter pw = new PrintWriter(f, StandardCharsets.UTF_8)) {
            pw.print('\ufeff');
            List<String> cols = new ArrayList<>(filas.get(0).keySet());
            pw.println(String.join(",", cols));
            for (Map<String, String> r : filas) {
                List<String> v = new ArrayList<>();
                for (String c : cols) v.add("\"" + r.getOrDefault(c, "").replace("\"", "\"\"") + "\"");
                pw.println(String.join(",", v));
            }
            info("Archivo guardado: " + f.getName());
        } catch (Exception e) { error("No se pudo guardar el archivo."); }
    }
}
