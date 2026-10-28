package pe.contadoreseirl.integration;

import java.net.SocketTimeoutException;
import java.util.Map;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import pe.contadoreseirl.config.AppProperties;

/**
 * Consulta de RUC a un proveedor SUNAT. URL y token vienen de variables de entorno.
 * Se espera un GET {SUNAT_API_URL}?numero={ruc} con "Authorization: Bearer {SUNAT_API_TOKEN}"
 * (formato típico de proveedores como apis.net.pe). Ajusta aquí si tu proveedor difiere.
 */
@Service
public class SunatService {
    public record Resultado(String estado, Map<String, Object> data, String error) {}

    private final AppProperties props;
    private final RestClient http;

    public SunatService(AppProperties props) {
        this.props = props;
        SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(props.sunat().timeoutMs());
        f.setReadTimeout(props.sunat().timeoutMs());
        this.http = RestClient.builder().requestFactory(f).build();
    }

    public Resultado consultar(String ruc) {
        if (props.sunat().url() == null || props.sunat().url().isBlank())
            return new Resultado("ERROR", null, "Integración SUNAT no configurada");
        try {
            Map<String, Object> body = http.get().uri(props.sunat().url() + "?numero=" + ruc)
                .header("Authorization", "Bearer " + props.sunat().token())
                .retrieve().body(new ParameterizedTypeReference<>() {});
            if (body == null || body.isEmpty()) return new Resultado("SIN_RESULTADOS", null, "Sin resultados");
            return new Resultado("SUCCESS", body, null);
        } catch (HttpClientErrorException.NotFound e) {
            return new Resultado("SIN_RESULTADOS", null, "Sin resultados");
        } catch (ResourceAccessException e) {
            boolean timeout = e.getCause() instanceof SocketTimeoutException;
            return new Resultado(timeout ? "TIMEOUT" : "ERROR", null, timeout ? "Tiempo de espera agotado" : "Servicio SUNAT no disponible");
        } catch (Exception e) {
            return new Resultado("ERROR", null, "Error consultando SUNAT");
        }
    }
}
