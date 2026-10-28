import { useMemo, useState } from 'react'
import { exportarCsv, exportarPdf, exportarXlsx, type Fila } from '../../lib/export'
import { Vacio } from '../Shell'

type Row = Record<string, any>
interface Props { clientes: Row[]; leads: Row[]; solicitudes: Row[]; contratados: Row[]; actividad: Row[]; servicios: Row[] }

export default function Reportes({ clientes, leads, solicitudes, contratados, actividad, servicios }: Props) {
  const [f, setF] = useState({ desde: '', hasta: '', estado: '', servicio: '', cliente: '' })
  const fecha = (r: Row) => String(r.created_at).slice(0, 10)
  const enRango = (r: Row) => (!f.desde || fecha(r) >= f.desde) && (!f.hasta || fecha(r) <= f.hasta)
  const hace30 = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10)

  const datasets: Record<string, Fila[]> = useMemo(() => {
    const est = (r: Row) => !f.estado || r.estado === f.estado
    const srv = (r: Row) => !f.servicio || r.servicio_id === f.servicio
    const cli = (r: Row) => !f.cliente || r.cliente_id === f.cliente || r.id === f.cliente
    const mapCliente = (c: Row): Fila => ({ Documento: c.documento, 'Razón social': c.razon_social, Tipo: c.tipo_cliente, Correo: c.correo, Teléfono: c.telefono, Estado: c.estado, Registro: fecha(c) })
    const porMes: Record<string, number> = {}
    actividad.filter(enRango).forEach(a => { const m = String(a.created_at).slice(0, 7); porMes[m] = (porMes[m] ?? 0) + 1 })
    return {
      'Clientes registrados': clientes.filter(c => enRango(c) && est(c) && cli(c)).map(mapCliente),
      'Nuevos clientes': clientes.filter(c => (f.desde ? enRango(c) : fecha(c) >= hace30) && est(c) && cli(c)).map(mapCliente),
      'Servicios contratados': contratados.filter(c => enRango(c) && est(c) && srv(c) && cli(c)).map((c): Fila => ({ Cliente: c.clientes?.razon_social, Servicio: c.servicios?.nombre, Estado: c.estado, Inicio: c.fecha_inicio, Fin: c.fecha_fin })),
      Leads: leads.filter(l => enRango(l) && est(l) && srv(l)).map((l): Fila => ({ Fecha: fecha(l), Nombre: l.nombre_completo, Documento: l.documento, Teléfono: l.telefono, Correo: l.correo, Servicio: l.servicios?.nombre, Estado: l.estado })),
      Solicitudes: solicitudes.filter(s => enRango(s) && est(s) && srv(s) && cli(s)).map((s): Fila => ({ Fecha: fecha(s), Cliente: s.clientes?.razon_social, Asunto: s.asunto, Servicio: s.servicios?.nombre, Estado: s.estado })),
      'Actividad mensual': Object.entries(porMes).sort().map(([Mes, Eventos]): Fila => ({ Mes, Eventos }))
    } as Record<string, Fila[]>
  }, [f, clientes, leads, solicitudes, contratados, actividad])

  const set = (k: string, v: string) => setF(x => ({ ...x, [k]: v }))
  const slug = (s: string) => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, '-')
  return (
    <div className="space-y-4">
      <div className="card grid gap-3 sm:grid-cols-5">
        <div><label className="label">Desde</label><input type="date" className="input" value={f.desde} onChange={e => set('desde', e.target.value)} /></div>
        <div><label className="label">Hasta</label><input type="date" className="input" value={f.hasta} onChange={e => set('hasta', e.target.value)} /></div>
        <div><label className="label">Estado</label><input className="input" placeholder="Ej: ACTIVO, NUEVO…" value={f.estado} onChange={e => set('estado', e.target.value.toUpperCase())} /></div>
        <div><label className="label">Servicio</label><select className="input" value={f.servicio} onChange={e => set('servicio', e.target.value)}><option value="">Todos</option>{servicios.map(s => <option key={s.id} value={s.id}>{s.nombre}</option>)}</select></div>
        <div><label className="label">Cliente</label><select className="input" value={f.cliente} onChange={e => set('cliente', e.target.value)}><option value="">Todos</option>{clientes.map(c => <option key={c.id} value={c.id}>{c.razon_social}</option>)}</select></div>
      </div>
      {Object.entries(datasets).map(([titulo, filas]) => (
        <div key={titulo} className="card">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="font-medium">{titulo}: <b>{filas.length}</b></span>
            <span className="flex gap-2">
              <button className="btn btn-ghost" disabled={!filas.length} onClick={() => exportarCsv(slug(titulo), filas)}>CSV</button>
              <button className="btn btn-ghost" disabled={!filas.length} onClick={() => exportarXlsx(slug(titulo), { [titulo]: filas })}>Excel</button>
              <button className="btn" disabled={!filas.length} onClick={() => exportarPdf(slug(titulo), titulo, filas)}>PDF</button>
            </span>
          </div>
          {filas.length > 0 && (
            <div className="mt-3 max-h-48 overflow-auto"><table className="w-full text-xs"><thead className="bg-slate-100 text-left"><tr>{Object.keys(filas[0]).map(c => <th key={c} className="p-1">{c}</th>)}</tr></thead>
              <tbody>{filas.slice(0, 10).map((r, i) => <tr key={i} className="border-t">{Object.values(r).map((v, j) => <td key={j} className="p-1">{String(v ?? '')}</td>)}</tr>)}</tbody></table>
              {filas.length > 10 && <p className="mt-1 text-xs text-slate-500">Vista previa de 10 filas; la exportación incluye todas.</p>}</div>)}
        </div>
      ))}
      <div className="card flex items-center justify-between"><span>Reporte completo (todas las hojas)</span>
        <button className="btn btn-gold" onClick={() => exportarXlsx('reporte-completo', datasets)}>Excel completo</button></div>
      {Object.values(datasets).every(d => d.length === 0) && <Vacio texto="No hay datos con los filtros seleccionados." />}
    </div>
  )
}
