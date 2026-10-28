package pe.contadoreseirl.controller;

import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import pe.contadoreseirl.dto.CrearAccesoRequest;
import pe.contadoreseirl.integration.SupabaseClient;
import pe.contadoreseirl.security.Authz;
import pe.contadoreseirl.validation.Validaciones;

/** Crea el acceso al portal de un cliente existente (usuario Auth con rol CLIENTE vinculado al cliente). */
@RestController
@RequestMapping("/api/clientes")
public class ClienteAccesoController {
    private final SupabaseClient supabase; private final Authz authz;
    public ClienteAccesoController(SupabaseClient supabase, Authz authz) { this.supabase = supabase; this.authz = authz; }

    @PostMapping("/{clienteId}/acceso")
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, String> crearAcceso(@PathVariable String clienteId, @Valid @RequestBody CrearAccesoRequest req, Authentication auth) {
        authz.requireContadorOAdmin(auth);
        Validaciones.exigirUuid(clienteId);
        Validaciones.exigirCorreo(req.correo());
        if (supabase.clienteUserId(clienteId) != null) throw new IllegalArgumentException("El cliente ya tiene acceso");
        Map<String, Object> user = supabase.adminCreateUser(req.correo().trim(), req.password(), "Cliente");
        String userId = String.valueOf(user.get("id"));
        try {
            supabase.setRole(userId, "CLIENTE");
            supabase.vincularCliente(clienteId, userId);
        } catch (RuntimeException e) {
            supabase.deleteAuthUser(userId);   // no deja usuarios huérfanos si falla la vinculación
            throw e;
        }
        return Map.of("userId", userId);
    }
}
