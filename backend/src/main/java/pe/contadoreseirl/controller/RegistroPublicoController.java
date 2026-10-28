package pe.contadoreseirl.controller;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClientResponseException;
import pe.contadoreseirl.dto.RegistroRequest;
import pe.contadoreseirl.integration.SunatService;
import pe.contadoreseirl.integration.SupabaseClient;
import pe.contadoreseirl.security.RateLimiter;
import pe.contadoreseirl.validation.Validaciones;

/**
 * Endpoints PÚBLICOS (sin sesión) para que un cliente se registre en la web con su RUC.
 * Solo se crea la cuenta si el RUC existe en SUNAT. Razón social, nombre comercial y dirección
 * se toman de la respuesta de SUNAT, nunca de lo que escribe el visitante.
 */
@RestController
@RequestMapping("/api/public")
public class RegistroPublicoController {
    private static final Logger log = LoggerFactory.getLogger(RegistroPublicoController.class);
    private static final long MIN = 60_000L;

    private final SunatService sunat;
    private final SupabaseClient supabase;
    private final RateLimiter limiter;
    private final String webUrl;

    public RegistroPublicoController(SunatService sunat, SupabaseClient supabase, RateLimiter limiter,
                                     @Value("${app.web-url:http://localhost:5173}") String webUrl) {
        this.sunat = sunat; this.supabase = supabase; this.limiter = limiter; this.webUrl = webUrl;
    }

    record DatosRuc(String razonSocial, String nombreComercial, String direccion, String estado, String condicion) {}

    /** Consulta un RUC para autocompletar el formulario. Devuelve solo los campos necesarios. */
    @GetMapping("/ruc/{ruc}")
    public ResponseEntity<Map<String, Object>> consultarRuc(@PathVariable String ruc, HttpServletRequest http) {
        if (!limiter.permitir("ruc:" + ip(http), 15, 10 * MIN))
            return msg(HttpStatus.TOO_MANY_REQUESTS, "Demasiadas consultas. Espera unos minutos.");
        if (!Validaciones.ruc(ruc)) return msg(HttpStatus.BAD_REQUEST, "RUC no válido");

        var r = sunat.consultar(ruc);
        guardarConsulta(ruc, r);
        if (!"SUCCESS".equals(r.estado())) return errorSunat(r);
        DatosRuc d = extraer(r.data());
        if (d.razonSocial().isEmpty()) {
            log.warn("Respuesta SUNAT sin razón social reconocible para el RUC {}; revisa los nombres de campo en extraer()", ruc);
            return msg(HttpStatus.SERVICE_UNAVAILABLE, "No pudimos verificar el RUC en este momento. Inténtalo en unos minutos.");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ruc", ruc);
        out.put("razonSocial", d.razonSocial());
        out.put("nombreComercial", d.nombreComercial());
        out.put("direccion", d.direccion());
        out.put("estado", d.estado());
        out.put("condicion", d.condicion());
        return ResponseEntity.ok(out);
    }

    /** Crea la cuenta solo si el RUC existe en SUNAT. Supabase envía el correo de confirmación. */
    @PostMapping("/registro")
    public ResponseEntity<Map<String, Object>> registrar(@Valid @RequestBody RegistroRequest req, HttpServletRequest http) {
        if (!limiter.permitir("reg-ip:" + ip(http), 5, 30 * MIN) || !limiter.permitir("reg-mail:" + req.correo().trim().toLowerCase(), 3, 60 * MIN))
            return msg(HttpStatus.TOO_MANY_REQUESTS, "Demasiados intentos. Espera unos minutos.");
        if (!Validaciones.ruc(req.ruc())) return msg(HttpStatus.BAD_REQUEST, "RUC no válido");
        if (!Validaciones.correo(req.correo().trim())) return msg(HttpStatus.BAD_REQUEST, "Correo no válido");
        if (!Validaciones.telefono(req.telefono().trim())) return msg(HttpStatus.BAD_REQUEST, "Teléfono no válido");

        var r = sunat.consultar(req.ruc());
        guardarConsulta(req.ruc(), r);
        if (!"SUCCESS".equals(r.estado())) return errorSunat(r);
        DatosRuc d = extraer(r.data());
        if (d.razonSocial().isEmpty()) {
            log.warn("Respuesta SUNAT sin razón social reconocible para el RUC {}; revisa los nombres de campo en extraer()", req.ruc());
            return msg(HttpStatus.SERVICE_UNAVAILABLE, "No pudimos verificar el RUC en este momento. Inténtalo en unos minutos.");
        }

        Map<String, Object> meta = new LinkedHashMap<>();
        meta.put("nombre_completo", Validaciones.limpiar(req.nombre()));
        meta.put("telefono", req.telefono().trim());
        meta.put("documento", req.ruc());
        meta.put("razon_social", d.razonSocial());
        meta.put("nombre_comercial", d.nombreComercial());
        meta.put("direccion", d.direccion());
        try {
            supabase.signup(req.correo().trim(), req.password(), meta, webUrl + "/login");
        } catch (RestClientResponseException e) {
            log.warn("Supabase rechazó el registro (HTTP {})", e.getStatusCode().value());
            if (e.getStatusCode().value() == 429) return msg(HttpStatus.TOO_MANY_REQUESTS, "Demasiados intentos. Espera unos minutos.");
            return msg(HttpStatus.BAD_REQUEST, "No se pudo crear la cuenta. Revisa los datos e inténtalo de nuevo.");
        }
        // Misma respuesta exista o no el correo: no revela qué correos ya tienen cuenta.
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.<String, Object>of("message", "Revisa tu correo para confirmar la cuenta"));
    }

    // ---------------- utilidades ----------------

    private void guardarConsulta(String ruc, SunatService.Resultado r) {
        try { supabase.logSunat(ruc, null, r.estado(), r.data(), r.error()); } catch (Exception ignored) { }
    }

    private static ResponseEntity<Map<String, Object>> errorSunat(SunatService.Resultado r) {
        if ("SIN_RESULTADOS".equals(r.estado()))
            return msg(HttpStatus.NOT_FOUND, "El RUC no existe en SUNAT. Revisa el número.");
        return msg(HttpStatus.SERVICE_UNAVAILABLE, "No pudimos verificar el RUC en este momento. Inténtalo en unos minutos.");
    }

    private static ResponseEntity<Map<String, Object>> msg(HttpStatus st, String m) {
        return ResponseEntity.status(st).body(Map.<String, Object>of("message", m));
    }

    /** Por defecto usa la IP directa. Detrás de un proxy, configura server.forward-headers-strategy. */
    private static String ip(HttpServletRequest r) { return r.getRemoteAddr(); }

    /** Tolera los nombres de campo más comunes de proveedores SUNAT (apis.net.pe, decolecta, etc.). */
    @SuppressWarnings("unchecked")
    private static DatosRuc extraer(Map<String, Object> d) {
        if (d.get("data") instanceof Map<?, ?> anidado) d = (Map<String, Object>) anidado;
        return new DatosRuc(
            texto(d, 200, "razonSocial", "razon_social", "nombre", "nombre_o_razon_social", "nombreORazonSocial"),
            texto(d, 200, "nombreComercial", "nombre_comercial"),
            texto(d, 300, "direccion", "domicilio_fiscal", "direccionCompleta"),
            texto(d, 40, "estado"),
            texto(d, 40, "condicion"));
    }

    private static String texto(Map<String, Object> d, int max, String... claves) {
        for (String k : claves) {
            Object v = d.get(k);
            if (v == null) continue;
            String s = Validaciones.limpiar(String.valueOf(v));
            if (!s.isEmpty() && !s.equals("-")) return s.length() > max ? s.substring(0, max) : s;
        }
        return "";
    }
}
