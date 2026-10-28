package pe.contadoreseirl.desktop;

import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class ConfigView {
    private ConfigView() {}

    static Tab crear(Api api, Runnable cerrarSesion) {
        Label estado = new Label();
        Button probar = Ui.btn("Probar conexión con el backend"), clave = Ui.btn("Cambiar mi contraseña"), salir = Ui.btnGold("Cerrar sesión");
        probar.setOnAction(e -> { estado.setText("Probando…"); Ui.async(api::backendDisponible, ok -> estado.setText(ok ? "Backend disponible ✔" : "Backend no disponible ✘"), er -> estado.setText(er.getMessage())); });
        clave.setOnAction(e -> Ui.formulario("Cambiar contraseña", new String[]{"Nueva contraseña"}, new String[]{""}).ifPresent(v -> {
            if (!Validators.clave(v.get(0))) { Ui.error("Mínimo 8 caracteres con mayúscula, minúscula y número."); return; }
            Ui.async(() -> { api.cambiarClave(v.get(0)); return true; }, ok -> Ui.info("Contraseña actualizada."), er -> Ui.error("No se pudo cambiar la contraseña.")); }));
        salir.setOnAction(e -> cerrarSesion.run());
        VBox v = new VBox(12, new Label("Usuario: " + api.email()), new Label("Rol: " + (api.esAdmin() ? "ADMINISTRADOR" : api.puedeEscribir() ? "CONTADOR" : "ASISTENTE")),
            new Label("Supabase: " + api.supabaseUrl()), new Label("Backend: " + api.backendUrl()), probar, estado, clave, salir);
        v.setPadding(new Insets(16)); return new Tab("Configuración", v);
    }
}
