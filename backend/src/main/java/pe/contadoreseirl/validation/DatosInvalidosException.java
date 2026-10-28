package pe.contadoreseirl.validation;

/** Error de validación de entrada (HTTP 400 con mensaje seguro para el usuario). */
public class DatosInvalidosException extends RuntimeException {
    public DatosInvalidosException(String message) { super(message); }
}
