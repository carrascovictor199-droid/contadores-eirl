package pe.contadoreseirl.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record CrearUsuarioRequest(
    @NotBlank @Email String correo,
    @NotBlank @Pattern(regexp = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$") String password,
    @NotBlank @Size(max = 150) String nombreCompleto,
    @NotBlank @Pattern(regexp = "ADMINISTRADOR|CONTADOR|ASISTENTE|CLIENTE") String rol) {}
