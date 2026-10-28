package pe.contadoreseirl.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Registro público de un cliente. La razón social y la dirección NO vienen del cliente: se toman de SUNAT. */
public record RegistroRequest(
    @NotBlank @Pattern(regexp = "^[0-9]{11}$") String ruc,
    @NotBlank @Size(min = 2, max = 150) String nombre,
    @NotBlank @Size(max = 20) String telefono,
    @NotBlank @Size(max = 254) String correo,
    @NotBlank @Size(max = 72) @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$") String password) {}
