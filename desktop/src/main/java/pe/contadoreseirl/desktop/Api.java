package pe.contadoreseirl.desktop;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

/** Cliente HTTP. Solo usa credenciales públicas (anon) y el JWT del usuario; sin secretos ni acceso directo a PostgreSQL. */
public class Api {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final String supabaseUrl = env("SUPABASE_URL", "");
    private final String anonKey = env("SUPABASE_ANON_KEY", "");
    private final String backend = env("DESKTOP_API_BASE_URL", "http://localhost:8080/api");
    private String token;
    private String email = "";
    private boolean admin, escritura;

    private static String env(String k, String d) { String v = System.getenv(k); return v == null || v.isBlank() ? d : v; }

    public boolean configurado() { return !supabaseUrl.isBlank() && !anonKey.isBlank(); }
    public String email() { return email; }
    public String supabaseUrl() { return supabaseUrl; }
    public String backendUrl() { return backend; }
    public boolean esAdmin() { return admin; }
    /** ADMINISTRADOR o CONTADOR: pueden crear/editar. El asistente solo consulta (RLS lo impone igualmente). */
    public boolean puedeEscribir() { return escritura; }

    public void login(String correo, String password) throws Exception {
        String body = JSON.writeValueAsString(Map.of("email", correo, "password", password));
        HttpRequest req = HttpRequest.newBuilder(URI.create(supabaseUrl + "/auth/v1/token?grant_type=password"))
            .header("apikey", anonKey).header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body)).build();
        HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (res.statusCode() != 200) throw new IllegalStateException("Correo o contraseña incorrectos");
        token = JSON.readTree(res.body()).get("access_token").asText();
        email = correo;
        if (!rpcBoolean("is_staff")) { token = null; throw new IllegalStateException("Esta aplicación es solo para el personal"); }
        admin = rpcBoolean("is_admin");
        escritura = rpcBoolean("is_contador_o_admin");
    }

    public void logout() { token = null; email = ""; admin = false; escritura = false; }

    /** GET PostgREST con el JWT del usuario: las políticas RLS deciden qué filas ve. */
    public JsonNode rest(String pathAndQuery) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(supabaseUrl + "/rest/v1/" + pathAndQuery)).header("apikey", anonKey).GET());
    }
    public JsonNode restPost(String table, Map<String, Object> body) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(supabaseUrl + "/rest/v1/" + table)).header("apikey", anonKey)
            .header("Content-Type", "application/json").header("Prefer", "return=representation")
            .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))));
    }
    public JsonNode patch(String pathAndQuery, Map<String, Object> body) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(supabaseUrl + "/rest/v1/" + pathAndQuery)).header("apikey", anonKey)
            .header("Content-Type", "application/json").method("PATCH", HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))));
    }
    public boolean rpcBoolean(String fn) throws Exception { return rpc(fn, Map.of()).asBoolean(); }
    public JsonNode rpc(String fn, Map<String, Object> args) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(supabaseUrl + "/rest/v1/rpc/" + fn)).header("apikey", anonKey)
            .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(args))));
    }

    public void cambiarClave(String nueva) throws Exception {
        send(HttpRequest.newBuilder(URI.create(supabaseUrl + "/auth/v1/user")).header("apikey", anonKey)
            .header("Content-Type", "application/json").PUT(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of("password", nueva)))));
    }

    // ---- Backend Spring Boot (operaciones sensibles) ----
    public JsonNode sunat(String ruc) throws Exception { return send(HttpRequest.newBuilder(URI.create(backend + "/sunat/ruc/" + ruc)).GET()); }
    public JsonNode backendPost(String path, Map<String, Object> body) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(backend + path)).header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))));
    }
    public JsonNode backendPatch(String path, Map<String, Object> body) throws Exception {
        return send(HttpRequest.newBuilder(URI.create(backend + path)).header("Content-Type", "application/json").method("PATCH", HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))));
    }
    public boolean backendDisponible() {
        try { return http.send(HttpRequest.newBuilder(URI.create(backend + "/health")).timeout(Duration.ofSeconds(5)).GET().build(), HttpResponse.BodyHandlers.discarding()).statusCode() == 200; }
        catch (Exception e) { return false; }
    }

    private JsonNode send(HttpRequest.Builder b) throws Exception {
        HttpRequest req = b.header("Authorization", "Bearer " + token).timeout(Duration.ofSeconds(15)).build();
        HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
        JsonNode node = res.body() == null || res.body().isBlank() ? JSON.createObjectNode() : JSON.readTree(res.body());
        if (res.statusCode() >= 400) {
            String m = node.hasNonNull("message") ? node.get("message").asText() : "Error " + res.statusCode();
            throw new IllegalStateException(m);
        }
        return node;
    }
}
