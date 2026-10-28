package pe.contadoreseirl.controller;

import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import pe.contadoreseirl.dto.CambiarRolRequest;
import pe.contadoreseirl.dto.CrearUsuarioRequest;
import pe.contadoreseirl.integration.SupabaseClient;
import pe.contadoreseirl.security.Authz;
import pe.contadoreseirl.validation.Validaciones;

/** Gestión de usuarios (solo ADMINISTRADOR). La identidad vive en Supabase Auth. */
@RestController
@RequestMapping("/api/admin/users")
public class UsuarioController {
    private final SupabaseClient supabase; private final Authz authz;
    public UsuarioController(SupabaseClient supabase, Authz authz) { this.supabase = supabase; this.authz = authz; }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, String> crear(@Valid @RequestBody CrearUsuarioRequest req, Authentication auth) {
        authz.requireAdmin(auth);
        Validaciones.exigirCorreo(req.correo());
        Map<String, Object> user = supabase.adminCreateUser(req.correo().trim(), req.password(), Validaciones.limpiar(req.nombreCompleto()));
        String id = String.valueOf(user.get("id"));
        supabase.setRole(id, req.rol());
        return Map.of("id", id);
    }

    @PatchMapping("/{id}/activo")
    public Map<String, Boolean> activar(@PathVariable String id, @RequestBody Map<String, Boolean> body, Authentication auth) {
        authz.requireAdmin(auth);
        validar(id, auth);
        boolean activo = Boolean.TRUE.equals(body.get("activo"));
        supabase.setProfileActive(id, activo);
        supabase.adminBan(id, !activo);        // además de desactivar el perfil, bloquea el acceso en Auth
        return Map.of("activo", activo);
    }

    @PatchMapping("/{id}/rol")
    public Map<String, String> rol(@PathVariable String id, @Valid @RequestBody CambiarRolRequest req, Authentication auth) {
        authz.requireAdmin(auth);
        validar(id, auth);
        supabase.setRole(id, req.rol());
        return Map.of("rol", req.rol());
    }

    /** Un administrador no puede quitarse a sí mismo el acceso ni el rol. */
    private void validar(String id, Authentication auth) {
        Validaciones.exigirUuid(id);
        if (id.equalsIgnoreCase(authz.jwt(auth).getSubject())) throw new IllegalArgumentException("No puedes modificar tu propio usuario");
    }
}
