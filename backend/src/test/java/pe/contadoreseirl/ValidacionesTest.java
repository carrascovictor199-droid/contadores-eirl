package pe.contadoreseirl;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import pe.contadoreseirl.validation.DatosInvalidosException;
import pe.contadoreseirl.validation.Validaciones;

class ValidacionesTest {
    @Test void rucValidoEInvalido() {
        assertTrue(Validaciones.ruc("20100070970"));
        assertFalse(Validaciones.ruc("20100070971"));   // dígito verificador
        assertFalse(Validaciones.ruc("99100070970"));   // prefijo
        assertFalse(Validaciones.ruc("2010007097"));    // longitud
        assertFalse(Validaciones.ruc(null));
    }
    @Test void dniYDocumento() {
        assertTrue(Validaciones.dni("12345678"));
        assertFalse(Validaciones.dni("1234567a"));
        assertTrue(Validaciones.documento("20100070970"));
        assertFalse(Validaciones.documento("123"));
    }
    @Test void correoExigeDominioConPunto() {
        assertTrue(Validaciones.correo("persona@empresa.com.pe"));
        assertFalse(Validaciones.correo("a@b"));
        assertFalse(Validaciones.correo("sin-arroba.com"));
        assertFalse(Validaciones.correo(""));
    }
    @Test void telefonoYUuid() {
        assertTrue(Validaciones.telefono("918 534 901"));
        assertFalse(Validaciones.telefono("12"));
        assertTrue(Validaciones.uuid("11111111-1111-1111-1111-111111111111"));
        assertFalse(Validaciones.uuid("../etc/passwd"));
    }
    @Test void limpiarNormalizaEspacios() {
        assertEquals("Juan Pérez", Validaciones.limpiar("  Juan \t  Pérez \n"));
        assertEquals("", Validaciones.limpiar(null));
    }
    @Test void exigirLanzaExcepcionControlada() {
        assertThrows(DatosInvalidosException.class, () -> Validaciones.exigirRuc("1"));
        assertThrows(DatosInvalidosException.class, () -> Validaciones.exigirCorreo("a@b"));
        assertThrows(DatosInvalidosException.class, () -> Validaciones.exigirUuid("x"));
    }
}
