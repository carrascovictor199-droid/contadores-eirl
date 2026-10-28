package pe.contadoreseirl.desktop;

import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;

public class MainApp extends Application {
    private final Api api = new Api();
    private Stage stage;

    @Override public void start(Stage s) {
        stage = s; s.setTitle("Contadores EIRL — Escritorio");
        mostrarLogin(); s.show();
    }

    private void mostrarLogin() {
        api.logout();
        TextField correo = new TextField(); correo.setPromptText("Correo");
        PasswordField clave = new PasswordField(); clave.setPromptText("Contraseña");
        Label estado = new Label(api.configurado() ? "" : "Configura SUPABASE_URL y SUPABASE_ANON_KEY (variables de entorno)");
        estado.setStyle("-fx-text-fill: #b91c1c;");
        Button entrar = Ui.btn("Iniciar sesión"); entrar.setDefaultButton(true);
        entrar.setOnAction(e -> {
            if (!Validators.correo(correo.getText().trim()) || clave.getText().isEmpty()) { estado.setText("Ingresa correo y contraseña válidos."); return; }
            entrar.setDisable(true); estado.setText("Ingresando…");
            Ui.async(() -> { api.login(correo.getText().trim(), clave.getText()); return true; },
                ok -> { stage.setScene(new Scene(vistaPrincipal(), 1150, 700)); stage.centerOnScreen(); },
                err -> { estado.setText(err.getMessage()); entrar.setDisable(false); });
        });
        Label t = new Label("Contadores EIRL"); t.setStyle("-fx-font-size: 26px; -fx-font-family: 'DM Serif Display', serif; -fx-text-fill: " + Ui.NAVY + ";");
        VBox box = new VBox(12, t, correo, clave, entrar, estado); box.setPadding(new Insets(32));
        stage.setScene(new Scene(box, 420, 340)); stage.centerOnScreen();
    }

    private TabPane vistaPrincipal() {
        javafx.stage.Window[] ventana = {stage};
        TabPane tabs = new TabPane(DashboardView.crear(api), ClientesView.crear(api), SunatView.crear(api), ServiciosView.crear(api),
            LeadsView.crear(api), SolicitudesView.crear(api), ReportesView.crear(api, ventana));
        if (api.esAdmin()) tabs.getTabs().add(UsuariosView.crear(api));
        tabs.getTabs().add(ConfigView.crear(api, this::mostrarLogin));
        tabs.setTabClosingPolicy(TabPane.TabClosingPolicy.UNAVAILABLE);
        return tabs;
    }

    public static void main(String[] args) { launch(args); }
}
