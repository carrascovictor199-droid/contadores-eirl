package pe.contadoreseirl.desktop;

import com.google.common.base.CharMatcher;
import com.google.common.base.Strings;
import com.google.common.collect.ImmutableSet;
import org.apache.commons.lang3.StringUtils;
import org.apache.commons.validator.routines.EmailValidator;

/** Validaciones del escritorio. Guava (CharMatcher, Strings, ImmutableSet) + Apache Commons (Validator, Lang3). */
public final class Validators {
    private static final CharMatcher DIGITOS = CharMatcher.inRange('0', '9');
    private static final ImmutableSet<String> PREFIJOS = ImmutableSet.of("10", "15", "16", "17", "20");
    private static final int[] PESOS = {5, 4, 3, 2, 7, 6, 5, 4, 3, 2};
    private static final EmailValidator CORREO = EmailValidator.getInstance(false);

    private Validators() {}

    public static boolean ruc(String r) {
        if (Strings.isNullOrEmpty(r) || r.length() != 11 || !DIGITOS.matchesAllOf(r) || !PREFIJOS.contains(r.substring(0, 2))) return false;
        int suma = 0;
        for (int i = 0; i < 10; i++) suma += (r.charAt(i) - '0') * PESOS[i];
        int dig = 11 - (suma % 11);
        if (dig == 10) dig = 0;
        if (dig == 11) dig = 1;
        return dig == r.charAt(10) - '0';
    }
    public static boolean documento(String d) { return !Strings.isNullOrEmpty(d) && ((d.length() == 8 && DIGITOS.matchesAllOf(d)) || ruc(d)); }
    public static boolean correo(String c) { return !Strings.isNullOrEmpty(c) && c.length() <= 254 && CORREO.isValid(c.trim()); }
    public static boolean telefono(String t) { return !Strings.isNullOrEmpty(t) && t.matches("^[0-9+() -]{6,20}$"); }
    public static boolean clave(String c) { return c != null && c.matches("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$"); }

    /** Normaliza espacios; devuelve "" si es nulo. */
    public static String limpiar(String t) { return StringUtils.normalizeSpace(StringUtils.defaultString(t)); }
    /** Nombre de archivo seguro: sin tildes ni símbolos. */
    public static String slug(String t) { return StringUtils.stripAccents(t).toLowerCase().replaceAll("[^a-z0-9]+", "-").replaceAll("^-|-$", ""); }
}
