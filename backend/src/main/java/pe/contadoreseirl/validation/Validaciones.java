package pe.contadoreseirl.validation;

import com.google.common.base.CharMatcher;
import com.google.common.base.Preconditions;
import com.google.common.base.Strings;
import com.google.common.collect.ImmutableSet;
import org.apache.commons.lang3.StringUtils;
import org.apache.commons.validator.routines.EmailValidator;

/**
 * Validaciones de servidor (la web y el escritorio validan también, pero el backend nunca confía en el cliente).
 * Guava: CharMatcher, Strings, ImmutableSet, Preconditions.  Apache Commons: Validator (correo) y Lang3 (texto).
 */
public final class Validaciones {
    private static final CharMatcher DIGITOS = CharMatcher.inRange('0', '9');
    private static final ImmutableSet<String> PREFIJOS_RUC = ImmutableSet.of("10", "15", "16", "17", "20");
    private static final int[] PESOS = {5, 4, 3, 2, 7, 6, 5, 4, 3, 2};
    private static final EmailValidator CORREO = EmailValidator.getInstance(false);

    private Validaciones() {}

    public static boolean dni(String d) { return !Strings.isNullOrEmpty(d) && d.length() == 8 && DIGITOS.matchesAllOf(d); }

    /** RUC peruano: 11 dígitos, prefijo válido y dígito verificador módulo 11. */
    public static boolean ruc(String r) {
        if (Strings.isNullOrEmpty(r) || r.length() != 11 || !DIGITOS.matchesAllOf(r) || !PREFIJOS_RUC.contains(r.substring(0, 2))) return false;
        int suma = 0;
        for (int i = 0; i < 10; i++) suma += (r.charAt(i) - '0') * PESOS[i];
        int dig = 11 - (suma % 11);
        if (dig == 10) dig = 0;
        if (dig == 11) dig = 1;
        return dig == r.charAt(10) - '0';
    }

    public static boolean documento(String d) { return dni(d) || ruc(d); }

    /** Más estricto que @Email de Jakarta: exige dominio con punto (rechaza "a@b"). */
    public static boolean correo(String c) { return !Strings.isNullOrEmpty(c) && c.length() <= 254 && CORREO.isValid(c); }

    public static boolean telefono(String t) { return !Strings.isNullOrEmpty(t) && t.matches("^[0-9+() -]{6,20}$"); }

    public static boolean uuid(String id) { return !Strings.isNullOrEmpty(id) && id.matches("[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"); }

    /** Quita espacios sobrantes y caracteres de control. */
    public static String limpiar(String texto) { return StringUtils.normalizeSpace(StringUtils.defaultString(texto)); }

    public static void exigirRuc(String r) { if (!ruc(r)) throw new DatosInvalidosException("RUC no válido"); }
    public static void exigirCorreo(String c) { if (!correo(c)) throw new DatosInvalidosException("Correo no válido"); }
    public static void exigirUuid(String id) { Preconditions.checkNotNull(id, "id"); if (!uuid(id)) throw new DatosInvalidosException("Identificador no válido"); }
}
