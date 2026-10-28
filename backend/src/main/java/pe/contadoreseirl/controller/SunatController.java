package pe.contadoreseirl.controller;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import pe.contadoreseirl.integration.SunatService;
import pe.contadoreseirl.integration.SupabaseClient;
import pe.contadoreseirl.security.Authz;
import pe.contadoreseirl.validation.Validaciones;

@RestController
@RequestMapping("/api")
public class SunatController {
    private final SunatService sunat; private final SupabaseClient supabase; private final Authz authz;
    public SunatController(SunatService sunat, SupabaseClient supabase, Authz authz) { this.sunat = sunat; this.supabase = supabase; this.authz = authz; }

    @GetMapping("/health")
    public Map<String, String> health() { return Map.of("status", "ok"); }

    @GetMapping("/sunat/ruc/{ruc}")
    public ResponseEntity<Map<String, Object>> ruc(@PathVariable String ruc, Authentication auth) {
        authz.requireStaff(auth);
        Validaciones.exigirRuc(ruc);
        var r = sunat.consultar(ruc);
        try { supabase.logSunat(ruc, authz.jwt(auth).getSubject(), r.estado(), r.data(), r.error()); } catch (Exception ignored) { }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("estado", r.estado()); out.put("data", r.data()); out.put("message", r.error());
        HttpStatus st = switch (r.estado()) { case "SUCCESS" -> HttpStatus.OK; case "SIN_RESULTADOS" -> HttpStatus.NOT_FOUND; case "TIMEOUT" -> HttpStatus.GATEWAY_TIMEOUT; default -> HttpStatus.BAD_GATEWAY; };
        return ResponseEntity.status(st).body(out);
    }
}
