import { describe, expect, it } from 'vitest'
import { toCsv, validarCorreo, validarDocumento, validarRuc, validarTelefono } from './validators'

describe('validarRuc', () => {
  it('acepta un RUC válido', () => expect(validarRuc('20100070970')).toBe(true))
  it('rechaza dígito verificador incorrecto', () => expect(validarRuc('20100070971')).toBe(false))
  it('rechaza longitud y prefijo inválidos', () => {
    expect(validarRuc('2010007097')).toBe(false)
    expect(validarRuc('99100070970')).toBe(false)
  })
})
describe('validarDocumento', () => {
  it('acepta DNI de 8 dígitos y RUC válido', () => { expect(validarDocumento('12345678')).toBe(true); expect(validarDocumento('20100070970')).toBe(true) })
  it('rechaza otros formatos', () => { expect(validarDocumento('1234567')).toBe(false); expect(validarDocumento('abcdefgh')).toBe(false) })
})
describe('correo y teléfono', () => {
  it('valida correos', () => { expect(validarCorreo('a@b.com')).toBe(true); expect(validarCorreo('a@b')).toBe(false) })
  it('valida teléfonos', () => { expect(validarTelefono('918 534 901')).toBe(true); expect(validarTelefono('12')).toBe(false) })
})
describe('toCsv', () => {
  it('escapa comillas y genera encabezado', () => {
    expect(toCsv([{ a: 'x"y', b: 1 }])).toBe('a,b\n"x""y","1"')
  })
  it('devuelve vacío sin filas', () => expect(toCsv([])).toBe(''))
})
