package pe.contadoreseirl.security;

import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import pe.contadoreseirl.exception.ForbiddenException;
import pe.contadoreseirl.integration.SupabaseClient;

@Component
public class Authz {
    private final SupabaseClient supabase;
    public Authz(SupabaseClient supabase) { this.supabase = supabase; }

    public Jwt jwt(Authentication a) { return ((JwtAuthenticationToken) a).getToken(); }

    public void requireStaff(Authentication a) {
        if (!supabase.rpcBoolean("is_staff", jwt(a).getTokenValue())) throw new ForbiddenException("Acceso solo para personal");
    }
    public void requireContadorOAdmin(Authentication a) {
        if (!supabase.rpcBoolean("is_contador_o_admin", jwt(a).getTokenValue())) throw new ForbiddenException("Requiere rol ADMINISTRADOR o CONTADOR");
    }
    public void requireAdmin(Authentication a) {
        if (!supabase.rpcBoolean("is_admin", jwt(a).getTokenValue())) throw new ForbiddenException("Acceso solo para administradores");
    }
}
