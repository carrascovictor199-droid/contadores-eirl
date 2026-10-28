package pe.contadoreseirl.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public record AppProperties(Supabase supabase, Cors cors, Sunat sunat) {
    public record Supabase(String url, String anonKey, String serviceRoleKey) {}
    public record Cors(String allowedOrigins) {}
    public record Sunat(String url, String token, int timeoutMs) {}
}
