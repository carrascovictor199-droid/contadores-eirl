export function validarRuc(ruc: string): boolean {
  if (!/^[0-9]{11}$/.test(ruc) || !['10', '15', '16', '17', '20'].includes(ruc.slice(0, 2))) return false
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
  const suma = pesos.reduce((acc, p, i) => acc + p * Number(ruc[i]), 0)
  let dig = 11 - (suma % 11)
  if (dig === 10) dig = 0
  if (dig === 11) dig = 1
  return dig === Number(ruc[10])
}
export const validarDocumento = (d: string) => /^[0-9]{8}$/.test(d) || validarRuc(d)
export const validarCorreo = (c: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c)
export const validarTelefono = (t: string) => /^[0-9+() -]{6,20}$/.test(t)

export function toCsv(rows: Record<string, unknown>[]): string {
  if (!rows.length) return ''
  const cols = Object.keys(rows[0])
  const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`
  return [cols.join(','), ...rows.map(r => cols.map(c => esc(r[c])).join(','))].join('\n')
}
export function descargarCsv(nombre: string, rows: Record<string, unknown>[]) {
  const blob = new Blob(['\ufeff' + toCsv(rows)], { type: 'text/csv;charset=utf-8' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob); a.download = nombre; a.click(); URL.revokeObjectURL(a.href)
}
