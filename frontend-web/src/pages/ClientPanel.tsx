import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { validarCorreo, validarTelefono } from '../lib/validators'
import Shell, { Estado, Vacio } from '../components/Shell'
import Documentos from '../components/Documentos'

type Row = Record<string, any>
const TABS = ['Resumen', 'Solicitudes', 'Servicios', 'Mensajes', 'Documentos', 'Notificaciones', 'Perfil']

export default function ClientPanel() {
  const { session } = useAuth()
  const [tab, setTab] = useState('Resumen')
  const [cliente, setCliente] = useState<Row | null>(null)
  const [solicitudes, setSolicitudes] = useState<Row[]>([])
  const [servicios, setServicios] = useState<Row[]>([])
  const [catalogo, setCatalogo] = useState<Row[]>([])
  const [mensajes, setMensajes] = useState<Row[]>([])
  const [notifs, setNotifs] = useState<Row[]>([])
  const [msg, setMsg] = useState({ error: '', ok: '' })
  const [nuevo, setNuevo] = useState({ asunto: '', descripcion: '', servicio_id: '' })
  const [texto, setTexto] = useState('')
  const [cargado, setCargado] = useState(false)
  const [auto, setAuto] = useState(false)
  const [vinc, setVinc] = useState({ doc: '', msg: '', error: '', busy: false })
  const [perfil, setPerfil] = useState({ telefono: '', direccion: '', correo: '', clave: '' })

  const cargar = useCallback(async () => {
    const [c, s, cs, m, n, cat] = await Promise.all([
      supabase.from('clientes').select('*').maybeSingle(),
      supabase.from('solicitudes').select('*, servicios(nombre)').order('created_at', { ascending: false }),
      supabase.from('cliente_servicio').select('*, servicios(nombre,descripcion)').order('created_at', { ascending: false }),
      supabase.from('mensajes').select('*').order('created_at', { ascending: true }),
      supabase.from('notificaciones').select('*').order('created_at', { ascending: false }),
      supabase.from('servicios').select('id,nombre').eq('activo', true)
    ])
    setCargado(true); setCliente(c.data); setSolicitudes(s.data ?? []); setServicios(cs.data ?? []); setMensajes(m.data ?? []); setNotifs(n.data ?? []); setCatalogo(cat.data ?? [])
    if (c.data) setPerfil(p => ({ ...p, telefono: c.data.telefono ?? '', direccion: c.data.direccion ?? '', correo: c.data.correo ?? '' }))
  }, [])
  useEffect(() => { cargar() }, [cargar])

  const aviso = (error = '', ok = '') => setMsg({ error, ok })

  async function vincular(doc: string) {
    setVinc(v => ({ ...v, msg: '', error: '', busy: true }))
    const { data, error } = await supabase.rpc('vincular_mi_cuenta', { p_documento: doc })
    if (error) {
      const m = error.message
      return setVinc(v => ({ ...v, busy: false, error: m.includes('Confirma tu correo') ? 'Primero confirma tu correo (revisa tu bandeja).' : m.includes('teléfono') ? 'Completa tu teléfono en el perfil.' : m.includes('Documento') ? 'Documento no válido.' : m.includes('no verificado') ? 'Tu RUC no pudo verificarse en SUNAT. Contacta al estudio.' : m.includes('Solo se pueden') ? 'Solo se pueden registrar empresas con RUC. Contacta al estudio.' : m.includes('razón social') ? 'Falta la razón social de tu empresa (edítala en tu registro o contacta al estudio).' : 'No se pudo vincular. Inténtalo más tarde.' }))
    }
    if (data === 'VINCULADO' || data === 'CREADO') { setVinc(v => ({ ...v, busy: false })); await cargar(); if (data === 'CREADO') aviso('', 'Tu portal fue creado con los datos de tu registro. El estudio los verificará en breve.') }
    else setVinc(v => ({ ...v, busy: false, msg: 'Recibimos tu solicitud. El estudio validará tu información y activará tu portal.' }))
  }
  useEffect(() => {
    const d = session?.user.user_metadata?.documento as string | undefined
    if (cargado && !cliente && d && !auto) { setAuto(true); setVinc(v => ({ ...v, doc: d })); vincular(d) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargado, cliente])

  async function crearSolicitud(e: FormEvent) {
    e.preventDefault(); aviso()
    if (!cliente) return aviso('Tu cuenta aún no está vinculada a un cliente. Contacta al estudio.')
    if (nuevo.asunto.trim().length < 3) return aviso('Escribe un asunto.')
    const { error } = await supabase.from('solicitudes').insert({ cliente_id: cliente.id, asunto: nuevo.asunto.trim(), descripcion: nuevo.descripcion || null, servicio_id: nuevo.servicio_id || null })
    if (error) return aviso('No se pudo crear la solicitud.')
    setNuevo({ asunto: '', descripcion: '', servicio_id: '' }); aviso('', 'Solicitud creada.'); cargar()
  }
  async function cancelar(id: string) {
    const { error } = await supabase.from('solicitudes').update({ estado: 'CANCELADA' }).eq('id', id)
    if (error) aviso('No se pudo cancelar.'); else { aviso('', 'Solicitud cancelada.'); cargar() }
  }
  async function enviarMensaje(e: FormEvent) {
    e.preventDefault(); aviso()
    if (!cliente || !texto.trim()) return
    const { error } = await supabase.from('mensajes').insert({ cliente_id: cliente.id, remitente_id: session!.user.id, contenido: texto.trim() })
    if (error) return aviso('No se pudo enviar el mensaje.')
    setTexto(''); cargar()
  }
  async function leer(id: string) { await supabase.from('notificaciones').update({ leida: true }).eq('id', id); cargar() }
  async function guardarPerfil(e: FormEvent) {
    e.preventDefault(); aviso()
    if (perfil.telefono && !validarTelefono(perfil.telefono)) return aviso('Teléfono no válido.')
    if (perfil.correo && !validarCorreo(perfil.correo)) return aviso('Correo no válido.')
    if (perfil.clave && !/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/.test(perfil.clave)) return aviso('Contraseña: mínimo 8, con mayúscula, minúscula y número.')
    if (cliente) {
      const { error } = await supabase.from('clientes').update({ telefono: perfil.telefono || null, direccion: perfil.direccion || null, correo: perfil.correo || null }).eq('id', cliente.id)
      if (error) return aviso('No se pudo guardar el perfil.')
    }
    if (perfil.clave) { const { error } = await supabase.auth.updateUser({ password: perfil.clave }); if (error) return aviso('No se pudo cambiar la contraseña.') }
    setPerfil(p => ({ ...p, clave: '' })); aviso('', 'Perfil actualizado.'); cargar()
  }

  return (
    <Shell titulo="Mi panel" tabs={TABS} tab={tab} onTab={t => { setTab(t); aviso() }}>
      <Estado error={msg.error} ok={msg.ok} />
      {cliente && cliente.verificado === false && <div className="card mb-4 border-l-4 !border-l-gold text-sm">Tus datos están <b>pendientes de verificación</b> por el estudio. Puedes usar tu portal mientras tanto.</div>}
      {cargado && !cliente && (
        <div className="card mb-4 border-l-4 !border-l-gold">
          <h3 className="text-lg">Activa tu portal</h3>
          <p className="text-sm text-slate-600">Tu cuenta aún no está vinculada a un expediente del estudio. Ingresa tu DNI o RUC para vincularla.</p>
          <div className="mt-2 flex flex-wrap gap-2"><input className="input max-w-xs" inputMode="numeric" maxLength={11} placeholder="DNI o RUC" value={vinc.doc} onChange={e => setVinc({ ...vinc, doc: e.target.value.replace(/\D/g, '') })} />
            <button className="btn" disabled={vinc.busy || !vinc.doc} onClick={() => vincular(vinc.doc)}>{vinc.busy ? 'Vinculando…' : 'Vincular mi cuenta'}</button></div>
          <Estado error={vinc.error} ok={vinc.msg} />
        </div>
      )}
      {tab === 'Resumen' && (
        <div className="grid gap-4 sm:grid-cols-3">
          <div className="card"><p className="label">Cliente</p><p className="font-serif text-xl text-navy">{cliente?.razon_social ?? 'Sin vincular'}</p></div>
          <div className="card"><p className="label">Solicitudes pendientes</p><p className="text-3xl text-navy">{solicitudes.filter(s => s.estado === 'PENDIENTE').length}</p></div>
          <div className="card"><p className="label">Notificaciones sin leer</p><p className="text-3xl text-navy">{notifs.filter(n => !n.leida).length}</p></div>
        </div>
      )}
      {tab === 'Solicitudes' && (
        <div className="space-y-4">
          <form onSubmit={crearSolicitud} className="card grid gap-3 sm:grid-cols-2">
            <div><label className="label">Asunto</label><input className="input" value={nuevo.asunto} onChange={e => setNuevo({ ...nuevo, asunto: e.target.value })} /></div>
            <div><label className="label">Servicio</label><select className="input" value={nuevo.servicio_id} onChange={e => setNuevo({ ...nuevo, servicio_id: e.target.value })}><option value="">—</option>{catalogo.map(s => <option key={s.id} value={s.id}>{s.nombre}</option>)}</select></div>
            <div className="sm:col-span-2"><label className="label">Descripción</label><textarea className="input" rows={3} value={nuevo.descripcion} onChange={e => setNuevo({ ...nuevo, descripcion: e.target.value })} /></div>
            <button className="btn sm:col-span-2">Crear solicitud</button>
          </form>
          {solicitudes.length === 0 ? <Vacio /> : solicitudes.map(s => (
            <div key={s.id} className="card"><div className="flex justify-between"><b>{s.asunto}</b><span className="rounded bg-gold/20 px-2 text-xs">{s.estado}</span></div>
              <p className="text-sm text-slate-600">{s.descripcion}</p>
              {s.respuesta && <p className="mt-2 rounded bg-slate-50 p-2 text-sm"><b>Respuesta:</b> {s.respuesta}</p>}
              {s.estado === 'PENDIENTE' && <button className="btn btn-ghost mt-2" onClick={() => cancelar(s.id)}>Cancelar</button>}</div>
          ))}
        </div>
      )}
      {tab === 'Servicios' && (servicios.length === 0 ? <Vacio texto="Aún no tienes servicios contratados." /> :
        <div className="grid gap-4 sm:grid-cols-2">{servicios.map(s => <div key={s.id} className="card"><b>{s.servicios?.nombre}</b><p className="text-sm text-slate-600">{s.servicios?.descripcion}</p><p className="mt-1 text-xs">Estado: {s.estado} · Desde {s.fecha_inicio}</p></div>)}</div>)}
      {tab === 'Mensajes' && (
        <div className="card">
          <div className="max-h-96 space-y-2 overflow-y-auto">{mensajes.length === 0 ? <Vacio texto="Sin mensajes." /> : mensajes.map(m => (
            <div key={m.id} className={`max-w-[80%] rounded-lg p-2 text-sm ${m.remitente_id === session!.user.id ? 'ml-auto bg-navy text-white' : 'bg-slate-100'}`}>{m.contenido}</div>))}</div>
          <form onSubmit={enviarMensaje} className="mt-3 flex gap-2"><input className="input" value={texto} onChange={e => setTexto(e.target.value)} placeholder="Escribe un mensaje…" /><button className="btn">Enviar</button></form>
        </div>
      )}
      {tab === 'Documentos' && (cliente ? <Documentos clienteId={cliente.id} puedeBorrar={false} /> : <Vacio texto="Tu cuenta aún no está vinculada a un cliente." />)}
      {tab === 'Notificaciones' && (notifs.length === 0 ? <Vacio /> : <div className="space-y-2">{notifs.map(n => (
        <div key={n.id} className={`card flex items-center justify-between ${n.leida ? 'opacity-60' : ''}`}><div><b>{n.titulo}</b><p className="text-sm">{n.mensaje}</p></div>
          {!n.leida && <button className="btn btn-ghost" onClick={() => leer(n.id)}>Marcar leída</button>}</div>))}</div>)}
      {tab === 'Perfil' && (
        <form onSubmit={guardarPerfil} className="card grid max-w-xl gap-3">
          <div><label className="label">Teléfono</label><input className="input" value={perfil.telefono} onChange={e => setPerfil({ ...perfil, telefono: e.target.value })} /></div>
          <div><label className="label">Dirección</label><input className="input" value={perfil.direccion} onChange={e => setPerfil({ ...perfil, direccion: e.target.value })} /></div>
          <div><label className="label">Correo de contacto</label><input className="input" value={perfil.correo} onChange={e => setPerfil({ ...perfil, correo: e.target.value })} /></div>
          <div><label className="label">Nueva contraseña (opcional)</label><input className="input" type="password" value={perfil.clave} onChange={e => setPerfil({ ...perfil, clave: e.target.value })} /></div>
          <button className="btn">Guardar</button>
        </form>
      )}
    </Shell>
  )
}
