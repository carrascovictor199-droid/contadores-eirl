package pe.contadoreseirl.integration;

import java.util.List;
import java.util.Map;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import pe.contadoreseirl.config.AppProperties;

/** Cliente de Supabase. La service_role key solo se usa aquí, en el servidor. */
@Component
public class SupabaseClient {
    private final AppProperties props;
    private final RestClient http = RestClient.create();

    public SupabaseClient(AppProperties props) { this.props = props; }

    /** Comprueba un rol con las funciones SQL (is_admin / is_staff) usando el JWT del propio usuario. */
    public boolean rpcBoolean(String fn, String userJwt) {
        Boolean r = http.post().uri(props.supabase().url() + "/rest/v1/rpc/" + fn)
            .header("apikey", props.supabase().anonKey())
            .header("Authorization", "Bearer " + userJwt)
            .contentType(MediaType.APPLICATION_JSON).body("{}")
            .retrieve().body(Boolean.class);
        return Boolean.TRUE.equals(r);
    }

    public Map<String, Object> adminCreateUser(String email, String password, String nombre) {
        return http.post().uri(props.supabase().url() + "/auth/v1/admin/users")
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("email", email, "password", password, "email_confirm", true,
                         "user_metadata", Map.of("nombre_completo", nombre)))
            .retrieve().body(new ParameterizedTypeReference<>() {});
    }

    public void adminBan(String userId, boolean ban) {
        http.put().uri(props.supabase().url() + "/auth/v1/admin/users/" + userId)
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("ban_duration", ban ? "876000h" : "none")).retrieve().toBodilessEntity();
    }

    public void setRole(String userId, String roleCode) {
        List<Map<String, Object>> roles = http.get()
            .uri(props.supabase().url() + "/rest/v1/roles?select=id&codigo=eq." + roleCode)
            .headers(h -> service(h)).retrieve().body(new ParameterizedTypeReference<>() {});
        if (roles == null || roles.isEmpty()) throw new IllegalArgumentException("Rol inexistente");
        http.delete().uri(props.supabase().url() + "/rest/v1/user_roles?user_id=eq." + userId)
            .headers(h -> service(h)).retrieve().toBodilessEntity();
        http.post().uri(props.supabase().url() + "/rest/v1/user_roles")
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("user_id", userId, "role_id", roles.get(0).get("id"))).retrieve().toBodilessEntity();
    }

    public void setProfileActive(String userId, boolean activo) {
        http.patch().uri(props.supabase().url() + "/rest/v1/profiles?id=eq." + userId)
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("activo", activo)).retrieve().toBodilessEntity();
    }

    public void logSunat(String ruc, String userId, String estado, Object respuesta, String error) {
        Map<String, Object> row = new java.util.HashMap<>();
        row.put("ruc", ruc); row.put("solicitado_por", userId); row.put("estado", estado);
        row.put("respuesta", respuesta); row.put("error", error);
        http.post().uri(props.supabase().url() + "/rest/v1/consultas_sunat")
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON).body(row)
            .retrieve().toBodilessEntity();
    }

    public String clienteUserId(String clienteId) {
        List<Map<String, Object>> r = http.get()
            .uri(props.supabase().url() + "/rest/v1/clientes?select=user_id&id=eq." + clienteId)
            .headers(h -> service(h)).retrieve().body(new ParameterizedTypeReference<>() {});
        if (r == null || r.isEmpty()) throw new IllegalArgumentException("Cliente inexistente");
        Object u = r.get(0).get("user_id");
        return u == null ? null : String.valueOf(u);
    }

    public void vincularCliente(String clienteId, String userId) {
        http.patch().uri(props.supabase().url() + "/rest/v1/clientes?id=eq." + clienteId)
            .headers(h -> service(h)).contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("user_id", userId)).retrieve().toBodilessEntity();
    }

    /** Registro normal de Supabase Auth (usa la anon key): Supabase envía el correo de confirmación. */
    public void signup(String email, String password, Map<String, Object> metadata, String redirectTo) {
        String redirect = java.net.URLEncoder.encode(redirectTo, java.nio.charset.StandardCharsets.UTF_8);
        http.post().uri(props.supabase().url() + "/auth/v1/signup?redirect_to=" + redirect)
            .header("apikey", props.supabase().anonKey())
            .contentType(MediaType.APPLICATION_JSON)
            .body(Map.of("email", email, "password", password, "data", metadata))
            .retrieve().toBodilessEntity();
    }

    public void deleteAuthUser(String userId) {
        http.delete().uri(props.supabase().url() + "/auth/v1/admin/users/" + userId)
            .headers(h -> service(h)).retrieve().toBodilessEntity();
    }

    private void service(org.springframework.http.HttpHeaders h) {
        String key = props.supabase().serviceRoleKey();
        h.set("apikey", key);
        // Las claves nuevas (sb_secret_...) no son JWT: solo van en "apikey". Las legacy (service_role, JWT) sí van también como Bearer.
        if (key != null && !key.startsWith("sb_")) h.set("Authorization", "Bearer " + key);
    }
}
