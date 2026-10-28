import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api, supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { validarCorreo, validarDocumento, validarRuc, validarTelefono } from '../lib/validators'
import Shell, { Estado, Vacio } from '../components/Shell'
import Reportes from '../components/staff/Reportes'
import Mensajes from '../components/staff/Mensajes'
import Usuarios from '../components/staff/Usuarios'
import Configuracion from '../components/staff/Configuracion'
import Documentos from '../components/Documentos'

type Row = Record<string, any>
const LEAD_ESTADOS = ['NUEVO', 'CONTACTADO', 'EN_NEGOCIACION', 'CONVERTIDO', 'NO_INTERESADO']
const SOL_ESTADOS = ['PENDIENTE', 'EN_REVISION', 'ATENDIDA', 'CANCELADA']
const count = (rows: Row[], k: string, vals: string[]) => vals.map(v => ({ name: v, total: rows.filter(r => r[k] === v).length }))

export default function StaffPanel() {
  const { isAdmin, roles } = useAuth()
  const puedeEscribir = roles.includes('ADMINISTRADOR') || roles.includes('CONTADOR')
  const tabs = ['Dashboard', 'Clientes', 'Leads', 'Solicitudes', 'Servicios', 'Mensajes', 'Documentos', 'Reportes', ...(isAdmin ? ['Usuarios'] : []), 'Configuración']
  const [tab, setTab] = useState('Dashboard')
  const [clientes, setClientes] = useState<Row[]>([]); const [leads, setLeads] = useState<Row[]>([])
  const [solicitudes, setSolicitudes] = useState<Row[]>([]); const [servicios, setServicios] = useState<Row[]>([])
  const [contratados, setContratados] = useState<Row[]>([]); const [actividad, setActividad] = useState<Row[]>([])
  const [msg, setMsg] = useState({ error: '', ok: '' }); const aviso = (error = '', ok = '') => setMsg({ error, ok })
  const [q, setQ] = useState('')
  const [nc, setNc] = useState({ documento: '', razon_social: '', nombre_comercial: '', direccion: '', telefono: '', correo: '' })
  const [editId, setEditId] = useState<string | null>(null)
  const [sunat, setSunat] = useState<'idle' | 'loading' | 'error'>('idle')
  const [resp, setResp] = useState<Record<string, string>>({})
  const [ns, setNs] = useState({ codigo: '', nombre: '', descripcion: '' })
  const [asig, setAsig] = useState({ cliente_id: '', servicio_id: '' })

  const cargar = useCallback(async () => {
    const [c, l, s, sv, cs, a] = await Promise.all([
      supabase.from('clientes').select('*').order('created_at', { ascending: false }),
      supabase.from('leads').select('*, servicios(nombre)').order('created_at', { ascending: false }),
      supabase.from('solicitudes').select('*, clientes(razon_social), servicios(nombre)').order('created_at', { ascending: false }),
      supabase.from('servicios').select('*').order('nombre'),
      supabase.from('cliente_servicio').select('*, clientes(razon_social), servicios(nombre)').order('created_at', { ascending: false }),
      supabase.from('actividad').select('*').order('created_at', { ascending: false }).limit(200)
    ])
    setClientes(c.data ?? []); setLeads(l.data ?? []); setSolicitudes(s.data ?? []); setServicios(sv.data ?? []); setContratados(cs.data ?? []); setActividad(a.data ?? [])
  }, [])
  useEffect(() => { cargar() }, [cargar])

  const err = (e: { message: string } | null, fallback: string) => e ? (e.message.includes('duplicate') ? 'Registro duplicado.' : fallback) : ''

  async function cambiarLead(id: string, estado: string) {
    const { error } = await supabase.from('leads').update({ estado }).eq('id', id); aviso(err(error, 'No se pudo cambiar el estado.')); cargar()
  }
  async function convertir(id: string) {
    const { error } = await supabase.rpc('convertir_lead_a_cliente', { p_lead_id: id })
    aviso(error ? 'No se pudo convertir (¿tienes permiso?).' : '', error ? '' : 'Lead convertido a cliente.'); cargar()
  }
  async function consultarSunat() {
    aviso(); if (!validarRuc(nc.documento)) return aviso('Ingresa un RUC válido de 11 dígitos.')
    setSunat('loading')
    try {
      const r = await api<{ data: Row }>(`/sunat/ruc/${nc.documento}`)
      const d = r.data
      setNc(x => ({ ...x, razon_social: d.razonSocial ?? d.nombre_o_razon_social ?? d.razon_social ?? x.razon_social, direccion: d.direccion ?? x.direccion }))
      setSunat('idle'); aviso('', `SUNAT: estado ${d.estado ?? '—'} · condición ${d.condicion ?? '—'}`)
    } catch (e) { setSunat('error'); aviso((e as Error).message) }
  }
  async function crearCliente(e: FormEvent) {
    e.preventDefault(); aviso()
    if (!validarDocumento(nc.documento)) return aviso('DNI/RUC no válido.')
    if (!nc.razon_social.trim()) return aviso('La razón social es obligatoria.')
    if (nc.telefono && !validarTelefono(nc.telefono)) return aviso('Teléfono no válido.')
    if (nc.correo && !validarCorreo(nc.correo)) return aviso('Correo no válido.')
    const datos = { razon_social: nc.razon_social.trim(), nombre_comercial: nc.nombre_comercial || null, direccion: nc.direccion || null, telefono: nc.telefono || null, correo: nc.correo || null }
    const { error } = editId
      ? await supabase.from('clientes').update(datos).eq('id', editId)
      : await supabase.from('clientes').insert({ ...datos, documento: nc.documento, tipo_cliente: nc.documento.startsWith('20') ? 'EMPRESA' : 'PERSONA_NATURAL' })
    if (error) return aviso(err(error, 'No se pudo guardar el cliente.'))
    setNc({ documento: '', razon_social: '', nombre_comercial: '', direccion: '', telefono: '', correo: '' }); aviso('', editId ? 'Cliente actualizado.' : 'Cliente registrado.'); setEditId(null); cargar()
  }
  function editarCliente(c: Row) {
    setEditId(c.id); window.scrollTo({ top: 0, behavior: 'smooth' })
    setNc({ documento: c.documento, razon_social: c.razon_social, nombre_comercial: c.nombre_comercial ?? '', direccion: c.direccion ?? '', telefono: c.telefono ?? '', correo: c.correo ?? '' })
  }
  async function crearAcceso(c: Row) {
    const correo = prompt(`Correo del cliente "${c.razon_social}" para su acceso al portal:`, c.correo ?? '')
    if (!correo) return
    const password = prompt('Contraseña inicial (mín. 8, con mayúscula, minúscula y número):')
    if (!password) return
    try { await api(`/clientes/${c.id}/acceso`, { method: 'POST', body: JSON.stringify({ correo, password }) }); aviso('', 'Acceso creado. Comparte las credenciales con el cliente.'); cargar() }
    catch (e) { aviso((e as Error).message) }
  }
  async function editarServicio(s: Row) {
    const nombre = prompt('Nombre del servicio:', s.nombre); if (!nombre) return
    const descripcion = prompt('Descripción:', s.descripcion ?? '')
    const { error } = await supabase.from('servicios').update({ nombre, descripcion: descripcion || null }).eq('id', s.id)
    aviso(err(error, 'No se pudo actualizar.'), error ? '' : 'Servicio actualizado.'); cargar()
  }
  async function verificarCliente(c: Row) {
    const { error } = await supabase.from('clientes').update({ verificado: true }).eq('id', c.id); aviso(err(error, 'Sin permiso.'), error ? '' : 'Cliente verificado.'); cargar()
  }
  async function toggleCliente(c: Row) {
    const { error } = await supabase.from('clientes').update({ estado: c.estado === 'ACTIVO' ? 'INACTIVO' : 'ACTIVO' }).eq('id', c.id); aviso(err(error, 'Sin permiso.')); cargar()
  }
  async function responder(s: Row, estado: string) {
    const { error } = await supabase.from('solicitudes').update({ estado, respuesta: resp[s.id] || s.respuesta || null }).eq('id', s.id)
    aviso(err(error, 'No se pudo actualizar (¿tienes permiso?).'), error ? '' : 'Solicitud actualizada.'); cargar()
  }
  async function crearServicio(e: FormEvent) {
    e.preventDefault(); aviso()
    const { error } = await supabase.from('servicios').insert({ codigo: ns.codigo.toUpperCase().replace(/\s+/g, '_'), nombre: ns.nombre, descripcion: ns.descripcion || null })
    if (error) return aviso(err(error, 'No se pudo crear (código en MAYÚSCULAS, sin espacios).'))
    setNs({ codigo: '', nombre: '', descripcion: '' }); aviso('', 'Servicio creado.'); cargar()
  }
  async function toggleServicio(s: Row) { const { error } = await supabase.from('servicios').update({ activo: !s.activo }).eq('id', s.id); aviso(err(error, 'Sin permiso.')); cargar() }
  async function asociar(e: FormEvent) {
    e.preventDefault(); aviso()
    const { error } = await supabase.from('cliente_servicio').insert(asig)
    aviso(error ? 'El cliente ya tiene ese servicio vigente o no tienes permiso.' : '', error ? '' : 'Servicio asociado.'); cargar()
  }
  async function estadoContrato(id: string, estado: string) { await supabase.from('cliente_servicio').update({ estado }).eq('id', id); cargar() }

  const clientesF = clientes.filter(c => `${c.razon_social} ${c.documento} ${c.correo ?? ''}`.toLowerCase().includes(q.toLowerCase()))
  const mensual = Object.entries(actividad.reduce<Record<string, number>>((acc, a) => { const m = a.created_at.slice(0, 7); acc[m] = (acc[m] ?? 0) + 1; return acc }, {})).sort().map(([mes, total]) => ({ mes, total }))
  const Chart = ({ data, x = 'name' }: { data: Row[]; x?: string }) => (
    <ResponsiveContainer width="100%" height={220}><BarChart data={data}><CartesianGrid strokeDasharray="3 3" /><XAxis dataKey={x} fontSize={11} /><YAxis allowDecimals={false} /><Tooltip /><Bar dataKey="total" fill="#1B3A6B" /></BarChart></ResponsiveContainer>)
  const Kpi = ({ t, v }: { t: string; v: number }) => <div className="card"><p className="label">{t}</p><p className="text-3xl text-navy">{v}</p></div>
  const hace30 = new Date(Date.now() - 30 * 864e5).toISOString()

  return (
    <Shell titulo="Panel del personal" tabs={tabs} tab={tab} onTab={t => { setTab(t); aviso() }}>
      <Estado error={msg.error} ok={msg.ok} />
      {tab === 'Dashboard' && (
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <Kpi t="Total clientes" v={clientes.length} /><Kpi t="Clientes nuevos (30 d)" v={clientes.filter(c => c.created_at >= hace30).length} />
            <Kpi t="Solicitudes pendientes" v={solicitudes.filter(s => s.estado === 'PENDIENTE').length} />
            <Kpi t="Servicios activos" v={contratados.filter(c => c.estado === 'ACTIVO').length} /><Kpi t="Leads nuevos" v={leads.filter(l => l.estado === 'NUEVO').length} />
          </div>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="card"><h3 className="mb-2">Leads por estado</h3><Chart data={count(leads, 'estado', LEAD_ESTADOS)} /></div>
            <div className="card"><h3 className="mb-2">Solicitudes por estado</h3><Chart data={count(solicitudes, 'estado', SOL_ESTADOS)} /></div>
            <div className="card"><h3 className="mb-2">Clientes por estado</h3><Chart data={count(clientes, 'estado', ['ACTIVO', 'INACTIVO'])} /></div>
            <div className="card"><h3 className="mb-2">Actividad mensual</h3>{mensual.length ? <Chart data={mensual} x="mes" /> : <Vacio />}</div>
          </div>
        </div>
      )}
      {tab === 'Clientes' && (
        <div className="space-y-4">
          {puedeEscribir && (
            <form onSubmit={crearCliente} className="card grid gap-3 sm:grid-cols-3">
              <h3 className="sm:col-span-3">{editId ? 'Editar cliente' : 'Registrar cliente'}</h3>
              <div><label className="label">DNI / RUC *</label><div className="flex gap-1"><input className="input" maxLength={11} disabled={!!editId} value={nc.documento} onChange={e => setNc({ ...nc, documento: e.target.value.replace(/\D/g, '') })} />
                <button type="button" className="btn btn-gold" disabled={sunat === 'loading' || !!editId} onClick={consultarSunat}>{sunat === 'loading' ? '…' : 'SUNAT'}</button></div></div>
              <div><label className="label">Razón social *</label><input className="input" value={nc.razon_social} onChange={e => setNc({ ...nc, razon_social: e.target.value })} /></div>
              <div><label className="label">Nombre comercial</label><input className="input" value={nc.nombre_comercial} onChange={e => setNc({ ...nc, nombre_comercial: e.target.value })} /></div>
              <div><label className="label">Dirección</label><input className="input" value={nc.direccion} onChange={e => setNc({ ...nc, direccion: e.target.value })} /></div>
              <div><label className="label">Teléfono</label><input className="input" value={nc.telefono} onChange={e => setNc({ ...nc, telefono: e.target.value })} /></div>
              <div><label className="label">Correo</label><input className="input" value={nc.correo} onChange={e => setNc({ ...nc, correo: e.target.value })} /></div>
              <div className="flex gap-2 sm:col-span-3"><button className="btn">{editId ? 'Guardar cambios' : 'Guardar cliente'}</button>{editId && <button type="button" className="btn btn-ghost" onClick={() => { setEditId(null); setNc({ documento: '', razon_social: '', nombre_comercial: '', direccion: '', telefono: '', correo: '' }) }}>Cancelar</button>}</div>
            </form>
          )}
          <input className="input" placeholder="Buscar por nombre, documento o correo…" value={q} onChange={e => setQ(e.target.value)} />
          {clientesF.length === 0 ? <Vacio /> : (
            <div className="card overflow-x-auto !p-0"><table className="w-full text-sm"><thead className="bg-slate-100 text-left"><tr><th className="p-2">Documento</th><th>Razón social</th><th>Tipo</th><th>Correo</th><th>Estado</th><th /></tr></thead>
              <tbody>{clientesF.map(c => <tr key={c.id} className="border-t"><td className="p-2">{c.documento}</td><td>{c.razon_social}</td><td>{c.tipo_cliente}</td><td>{c.correo}</td><td>{c.estado}{c.verificado === false && <span className="ml-1 rounded bg-amber-100 px-1 text-xs text-amber-800">Sin verificar</span>}</td>
                <td className="space-x-1 whitespace-nowrap">{puedeEscribir && <><button className="btn btn-ghost !py-1" onClick={() => editarCliente(c)}>Editar</button>{!c.user_id && <button className="btn btn-ghost !py-1" onClick={() => crearAcceso(c)}>Acceso</button>}{c.verificado === false && <button className="btn btn-gold !py-1" onClick={() => verificarCliente(c)}>Verificar</button>}<button className="btn btn-ghost !py-1" onClick={() => toggleCliente(c)}>{c.estado === 'ACTIVO' ? 'Desactivar' : 'Activar'}</button></>}</td></tr>)}</tbody></table></div>)}
        </div>
      )}
      {tab === 'Leads' && (leads.length === 0 ? <Vacio /> : (
        <div className="card overflow-x-auto !p-0"><table className="w-full text-sm"><thead className="bg-slate-100 text-left"><tr><th className="p-2">Fecha</th><th>Nombre</th><th>Documento</th><th>Contacto</th><th>Servicio</th><th>Estado</th><th /></tr></thead>
          <tbody>{leads.map(l => <tr key={l.id} className="border-t align-top"><td className="p-2">{l.created_at.slice(0, 10)}</td><td>{l.nombre_completo}<div className="text-xs text-slate-500">{l.empresa}</div></td><td>{l.documento}</td>
            <td>{l.telefono}<div className="text-xs">{l.correo}</div></td><td>{l.servicios?.nombre}</td>
            <td>{l.estado === 'CONVERTIDO' ? 'CONVERTIDO' : <select className="input !py-1" value={l.estado} onChange={e => cambiarLead(l.id, e.target.value)}>{LEAD_ESTADOS.filter(x => x !== 'CONVERTIDO').map(x => <option key={x}>{x}</option>)}</select>}</td>
            <td>{puedeEscribir && l.estado !== 'CONVERTIDO' && <button className="btn btn-gold !py-1" onClick={() => convertir(l.id)}>Convertir</button>}</td></tr>)}</tbody></table></div>))}
      {tab === 'Solicitudes' && (solicitudes.length === 0 ? <Vacio /> : (
        <div className="space-y-3">{solicitudes.map(s => (
          <div key={s.id} className="card"><div className="flex justify-between"><b>{s.asunto}</b><span className="rounded bg-gold/20 px-2 text-xs">{s.estado}</span></div>
            <p className="text-xs text-slate-500">{s.clientes?.razon_social} · {s.servicios?.nombre ?? 'Sin servicio'} · {s.created_at.slice(0, 10)}</p><p className="my-1 text-sm">{s.descripcion}</p>
            {puedeEscribir && s.estado !== 'CANCELADA' && (<div className="mt-2 flex flex-wrap gap-2"><input className="input flex-1" placeholder="Respuesta…" defaultValue={s.respuesta ?? ''} onChange={e => setResp({ ...resp, [s.id]: e.target.value })} />
              <button className="btn btn-ghost" onClick={() => responder(s, 'EN_REVISION')}>En revisión</button><button className="btn" onClick={() => responder(s, 'ATENDIDA')}>Atender</button></div>)}</div>))}</div>))}
      {tab === 'Servicios' && (
        <div className="space-y-4">
          {puedeEscribir && (<div className="grid gap-4 md:grid-cols-2">
            <form onSubmit={crearServicio} className="card space-y-2"><h3>Nuevo servicio</h3>
              <input className="input" placeholder="CÓDIGO_EN_MAYÚSCULAS" value={ns.codigo} onChange={e => setNs({ ...ns, codigo: e.target.value })} />
              <input className="input" placeholder="Nombre" value={ns.nombre} onChange={e => setNs({ ...ns, nombre: e.target.value })} />
              <input className="input" placeholder="Descripción" value={ns.descripcion} onChange={e => setNs({ ...ns, descripcion: e.target.value })} /><button className="btn">Crear</button></form>
            <form onSubmit={asociar} className="card space-y-2"><h3>Asociar servicio a cliente</h3>
              <select className="input" required value={asig.cliente_id} onChange={e => setAsig({ ...asig, cliente_id: e.target.value })}><option value="">Cliente…</option>{clientes.filter(c => c.estado === 'ACTIVO').map(c => <option key={c.id} value={c.id}>{c.razon_social}</option>)}</select>
              <select className="input" required value={asig.servicio_id} onChange={e => setAsig({ ...asig, servicio_id: e.target.value })}><option value="">Servicio…</option>{servicios.filter(s => s.activo).map(s => <option key={s.id} value={s.id}>{s.nombre}</option>)}</select><button className="btn">Asociar</button></form></div>)}
          <div className="card"><h3 className="mb-2">Catálogo</h3>{servicios.map(s => <div key={s.id} className="flex items-center justify-between border-t py-2 text-sm"><span>{s.nombre} <span className="text-xs text-slate-500">({s.codigo})</span></span>
            {puedeEscribir && <span className="space-x-1"><button className="btn btn-ghost !py-1" onClick={() => editarServicio(s)}>Editar</button><button className="btn btn-ghost !py-1" onClick={() => toggleServicio(s)}>{s.activo ? 'Desactivar' : 'Activar'}</button></span>}</div>)}</div>
          <div className="card"><h3 className="mb-2">Servicios contratados</h3>{contratados.length === 0 ? <Vacio /> : contratados.map(c => <div key={c.id} className="flex items-center justify-between border-t py-2 text-sm"><span>{c.clientes?.razon_social} — {c.servicios?.nombre}</span>
            {puedeEscribir ? <select className="input !w-auto !py-1" value={c.estado} onChange={e => estadoContrato(c.id, e.target.value)}>{['ACTIVO', 'PAUSADO', 'FINALIZADO', 'CANCELADO'].map(x => <option key={x}>{x}</option>)}</select> : c.estado}</div>)}</div>
        </div>
      )}
      {tab === 'Mensajes' && <Mensajes clientes={clientes} />}
      {tab === 'Documentos' && <Documentos clientes={clientes} puedeBorrar={puedeEscribir} />}
      {tab === 'Reportes' && <Reportes clientes={clientes} leads={leads} solicitudes={solicitudes} contratados={contratados} actividad={actividad} servicios={servicios} />}
      {tab === 'Usuarios' && isAdmin && <Usuarios />}
      {tab === 'Configuración' && <Configuracion />}
    </Shell>
  )
}
