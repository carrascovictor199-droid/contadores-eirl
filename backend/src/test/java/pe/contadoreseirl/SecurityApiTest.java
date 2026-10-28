package pe.contadoreseirl;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import pe.contadoreseirl.integration.SupabaseClient;

@SpringBootTest
@AutoConfigureMockMvc
class SecurityApiTest {
    @Autowired MockMvc mvc;
    @MockBean SupabaseClient supabase;

    private static final String UID = "11111111-1111-1111-1111-111111111111";
    private static final String OTHER = "22222222-2222-2222-2222-222222222222";

    @Test void healthEsPublico() throws Exception {
        mvc.perform(get("/api/health")).andExpect(status().isOk()).andExpect(jsonPath("$.status").value("ok"));
    }

    @Test void sunatSinTokenEs401() throws Exception {
        mvc.perform(get("/api/sunat/ruc/20100070970")).andExpect(status().isUnauthorized());
    }

    @Test void sunatConClienteEs403() throws Exception {
        when(supabase.rpcBoolean(eq("is_staff"), any())).thenReturn(false);
        mvc.perform(get("/api/sunat/ruc/20100070970").with(jwt().jwt(j -> j.subject(UID)))).andExpect(status().isForbidden());
    }

    @Test void sunatPersonalConRucInvalidoEs400() throws Exception {
        when(supabase.rpcBoolean(eq("is_staff"), any())).thenReturn(true);
        mvc.perform(get("/api/sunat/ruc/123").with(jwt().jwt(j -> j.subject(UID)))).andExpect(status().isBadRequest());
    }

    @Test void sunatSinConfigurarDevuelveErrorControlado() throws Exception {
        when(supabase.rpcBoolean(eq("is_staff"), any())).thenReturn(true);
        mvc.perform(get("/api/sunat/ruc/20100070970").with(jwt().jwt(j -> j.subject(UID))))
            .andExpect(status().isBadGateway()).andExpect(jsonPath("$.estado").value("ERROR"));
    }

    @Test void crearUsuarioRequiereAdmin() throws Exception {
        when(supabase.rpcBoolean(eq("is_admin"), any())).thenReturn(false);
        mvc.perform(post("/api/admin/users").with(jwt().jwt(j -> j.subject(UID))).contentType(MediaType.APPLICATION_JSON)
            .content("{\"correo\":\"a@b.com\",\"password\":\"Abcdefg1\",\"nombreCompleto\":\"X\",\"rol\":\"CONTADOR\"}"))
            .andExpect(status().isForbidden());
        verify(supabase, never()).adminCreateUser(any(), any(), any());
    }

    @Test void crearUsuarioValidaPasswordDebil() throws Exception {
        when(supabase.rpcBoolean(eq("is_admin"), any())).thenReturn(true);
        mvc.perform(post("/api/admin/users").with(jwt().jwt(j -> j.subject(UID))).contentType(MediaType.APPLICATION_JSON)
            .content("{\"correo\":\"a@b.com\",\"password\":\"123\",\"nombreCompleto\":\"X\",\"rol\":\"CONTADOR\"}"))
            .andExpect(status().isBadRequest());
    }

    @Test void adminNoPuedeDesactivarseASiMismo() throws Exception {
        when(supabase.rpcBoolean(eq("is_admin"), any())).thenReturn(true);
        mvc.perform(patch("/api/admin/users/" + UID + "/activo").with(jwt().jwt(j -> j.subject(UID)))
            .contentType(MediaType.APPLICATION_JSON).content("{\"activo\":false}")).andExpect(status().isBadRequest());
    }

    @Test void adminDesactivaOtroUsuario() throws Exception {
        when(supabase.rpcBoolean(eq("is_admin"), any())).thenReturn(true);
        mvc.perform(patch("/api/admin/users/" + OTHER + "/activo").with(jwt().jwt(j -> j.subject(UID)))
            .contentType(MediaType.APPLICATION_JSON).content("{\"activo\":false}")).andExpect(status().isOk());
        verify(supabase).adminBan(OTHER, true);
    }

    @Test void accesoClienteRequiereContadorOAdmin() throws Exception {
        when(supabase.rpcBoolean(eq("is_contador_o_admin"), any())).thenReturn(false);
        mvc.perform(post("/api/clientes/" + OTHER + "/acceso").with(jwt().jwt(j -> j.subject(UID))).contentType(MediaType.APPLICATION_JSON)
            .content("{\"correo\":\"c@d.com\",\"password\":\"Abcdefg1\"}")).andExpect(status().isForbidden());
    }

    @Test void accesoClienteNoDuplicaUsuario() throws Exception {
        when(supabase.rpcBoolean(eq("is_contador_o_admin"), any())).thenReturn(true);
        when(supabase.clienteUserId(OTHER)).thenReturn(UID);
        mvc.perform(post("/api/clientes/" + OTHER + "/acceso").with(jwt().jwt(j -> j.subject(UID))).contentType(MediaType.APPLICATION_JSON)
            .content("{\"correo\":\"c@d.com\",\"password\":\"Abcdefg1\"}")).andExpect(status().isBadRequest());
        verify(supabase, never()).adminCreateUser(any(), any(), any());
    }
}
