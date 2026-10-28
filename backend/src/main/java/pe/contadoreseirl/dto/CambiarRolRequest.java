package pe.contadoreseirl.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record CambiarRolRequest(@NotBlank @Pattern(regexp = "ADMINISTRADOR|CONTADOR|ASISTENTE|CLIENTE") String rol) {}
