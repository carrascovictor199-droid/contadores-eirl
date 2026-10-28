import * as XLSX from 'xlsx'
import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'
import { descargarCsv } from './validators'

export type Fila = Record<string, string | number | boolean | null>

export function exportarCsv(nombre: string, filas: Fila[]) { descargarCsv(`${nombre}.csv`, filas) }

/** Excel (.xlsx). Acepta varias hojas. */
export function exportarXlsx(nombre: string, hojas: Record<string, Fila[]>) {
  const wb = XLSX.utils.book_new()
  Object.entries(hojas).forEach(([hoja, filas]) =>
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(filas.length ? filas : [{ Sin_datos: '' }]), hoja.slice(0, 31)))
  XLSX.writeFile(wb, `${nombre}.xlsx`)
}

/** PDF con tabla y encabezado corporativo. */
export function exportarPdf(nombre: string, titulo: string, filas: Fila[]) {
  const doc = new jsPDF({ orientation: 'landscape' })
  doc.setFillColor(27, 58, 107); doc.rect(0, 0, doc.internal.pageSize.getWidth(), 18, 'F')
  doc.setTextColor(255, 255, 255); doc.setFontSize(14); doc.text(`Contadores EIRL — ${titulo}`, 10, 12)
  doc.setTextColor(0, 0, 0); doc.setFontSize(9); doc.text(`Generado: ${new Date().toLocaleString('es-PE')}`, 10, 25)
  const cols = filas.length ? Object.keys(filas[0]) : ['Sin datos']
  autoTable(doc, {
    startY: 29, head: [cols], body: filas.map(f => cols.map(c => String(f[c] ?? ''))),
    headStyles: { fillColor: [27, 58, 107], textColor: [200, 168, 75] }, styles: { fontSize: 8 }
  })
  doc.save(`${nombre}.pdf`)
}
