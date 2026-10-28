import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { validarCorreo, validarDocumento, validarTelefono } from '../lib/validators'
import { Estado } from '../components/Shell'

interface Servicio { id: string; nombre: string; descripcion: string | null; icono: string | null }
const ICONOS: Record<string, string> = { calculator: '🧮', 'file-text': '📄', 'book-open': '📘', scale: '⚖️', briefcase: '💼', 'more-horizontal': '✨' }
// Los testimonios reales se cargan aquí cuando existan (no se inventan).
const TESTIMONIOS: { texto: string; autor: string }[] = []
const BENEFICIOS = ['Atención personalizada de contadores colegiados', 'Cumplimiento tributario puntual ante SUNAT', 'Portal en línea para seguir tus servicios y solicitudes', 'Información protegida con seguridad empresarial']

export default function Home() {
  const [servicios, setServicios] = useState<Servicio[]>([])
  const [form, setForm] = useState({ nombre: '', documento: '', empresa: '', telefono: '', correo: '', servicio: '', mensaje: '' })
  const [estado, setEstado] = useState<'idle' | 'loading' | 'ok'>('idle')
  const [error, setError] = useState('')

  useEffect(() => { supabase.from('servicios').select('id,nombre,descripcion,icono').eq('activo', true).order('nombre').then(({ data }) => setServicios((data as Servicio[]) ?? [])) }, [])
  const set = (k: string, v: string) => setForm(f => ({ ...f, [k]: v }))

  async function enviar(e: FormEvent) {
    e.preventDefault(); setError('')
    if (form.nombre.trim().length < 2) return setError('Ingresa tu nombre completo.')
    if (!validarDocumento(form.documento)) return setError('DNI (8 dígitos) o RUC (11 dígitos) no válido.')
    if (!validarTelefono(form.telefono)) return setError('Teléfono no válido.')
    if (!validarCorreo(form.correo)) return setError('Correo no válido.')
    setEstado('loading')
    // Sin .select(): el visitante anónimo solo tiene permiso de inserción (RLS).
    const { error: err } = await supabase.from('leads').insert({
      nombre_completo: form.nombre.trim(), documento: form.documento, empresa: form.empresa || null,
      telefono: form.telefono, correo: form.correo, servicio_id: form.servicio || null, mensaje: form.mensaje || null
    })
    if (err) { setEstado('idle'); setError('No pudimos registrar tu solicitud. Inténtalo nuevamente.') } else setEstado('ok')
  }

  return (
    <div>
      <header className="sticky top-0 z-10 bg-navy text-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <span className="font-serif text-2xl">Contadores <span className="text-gold">EIRL</span></span>
          <nav className="hidden gap-6 text-sm md:flex">
            <a href="#inicio">Inicio</a><a href="#servicios">Servicios</a><a href="#nosotros">Nosotros</a><a href="#contacto">Contacto</a>
          </nav>
          <span className="flex gap-2"><Link to="/login" className="btn btn-ghost !text-white !border-white/40">Ingresar</Link><Link to="/registro" className="btn btn-ghost !text-white !border-white/40 hidden sm:inline-flex">Crear cuenta</Link><a href="#contacto" className="btn btn-gold">Solicitar asesoría</a></span>
        </div>
      </header>

      <section id="inicio" className="bg-gradient-to-br from-navy to-[#10264a] py-24 text-center text-white">
        <div className="mx-auto max-w-3xl px-4">
          <h1 className="!text-white text-4xl md:text-6xl">Tu tranquilidad contable y tributaria</h1>
          <p className="mt-4 text-lg text-white/80">Contabilidad, declaraciones y asesoría para que tu empresa crezca con orden y cumplimiento.</p>
          <a href="#contacto" className="btn btn-gold mt-8 !px-8 !py-3">Solicitar asesoría</a>
        </div>
      </section>

      <section id="servicios" className="mx-auto max-w-6xl px-4 py-16">
        <h2 className="mb-8 text-center text-3xl">Nuestros servicios</h2>
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {servicios.map(s => (
            <div key={s.id} className="card">
              <div className="text-3xl">{ICONOS[s.icono ?? ''] ?? '📊'}</div>
              <h3 className="mt-2 text-xl">{s.nombre}</h3>
              <p className="mt-1 text-sm text-slate-600">{s.descripcion}</p>
              <button className="btn btn-ghost mt-4" onClick={() => { set('servicio', s.id); location.hash = '#contacto' }}>Solicitar</button>
            </div>
          ))}
        </div>
      </section>

      <section id="nosotros" className="bg-white py-16">
        <div className="mx-auto max-w-6xl px-4">
          <h2 className="mb-8 text-center text-3xl">¿Por qué elegirnos?</h2>
          <div className="grid gap-4 sm:grid-cols-2">{BENEFICIOS.map(b => <div key={b} className="card border-l-4 !border-l-gold">{b}</div>)}</div>
        </div>
      </section>

      {TESTIMONIOS.length > 0 && (
        <section className="mx-auto max-w-6xl px-4 py-16">
          <h2 className="mb-8 text-center text-3xl">Testimonios</h2>
          <div className="grid gap-5 md:grid-cols-3">{TESTIMONIOS.map(t => <blockquote key={t.autor} className="card">“{t.texto}”<footer className="mt-2 text-sm text-slate-500">— {t.autor}</footer></blockquote>)}</div>
        </section>
      )}

      <section id="contacto" className="bg-navy py-16">
        <div className="mx-auto max-w-2xl px-4">
          <div className="card">
            {estado === 'ok' ? (
              <div className="py-8 text-center"><div className="text-5xl">✅</div><h2 className="mt-2 text-2xl">¡Solicitud recibida!</h2>
                <p className="mt-2 text-slate-600">Nuestro equipo te contactará muy pronto.</p>
                <button className="btn mt-4" onClick={() => { setEstado('idle'); setForm({ nombre: '', documento: '', empresa: '', telefono: '', correo: '', servicio: '', mensaje: '' }) }}>Enviar otra</button></div>
            ) : (
              <form onSubmit={enviar} className="grid gap-3 sm:grid-cols-2">
                <h2 className="text-2xl sm:col-span-2">Solicitar asesoría</h2>
                <div><label className="label">Nombre completo *</label><input className="input" value={form.nombre} onChange={e => set('nombre', e.target.value)} /></div>
                <div><label className="label">DNI / RUC *</label><input className="input" inputMode="numeric" maxLength={11} value={form.documento} onChange={e => set('documento', e.target.value.replace(/\D/g, ''))} /></div>
                <div><label className="label">Empresa / razón social</label><input className="input" value={form.empresa} onChange={e => set('empresa', e.target.value)} /></div>
                <div><label className="label">Teléfono *</label><input className="input" value={form.telefono} onChange={e => set('telefono', e.target.value)} /></div>
                <div><label className="label">Correo electrónico *</label><input className="input" type="email" value={form.correo} onChange={e => set('correo', e.target.value)} /></div>
                <div><label className="label">Servicio de interés</label>
                  <select className="input" value={form.servicio} onChange={e => set('servicio', e.target.value)}><option value="">Seleccionar…</option>{servicios.map(s => <option key={s.id} value={s.id}>{s.nombre}</option>)}</select></div>
                <div className="sm:col-span-2"><label className="label">Mensaje</label><textarea className="input" rows={3} maxLength={2000} value={form.mensaje} onChange={e => set('mensaje', e.target.value)} /></div>
                <div className="sm:col-span-2"><Estado error={error} /><button className="btn btn-gold w-full" disabled={estado === 'loading'}>{estado === 'loading' ? 'Enviando…' : 'Enviar solicitud'}</button></div>
              </form>
            )}
          </div>
        </div>
      </section>
      <footer className="bg-[#10264a] py-6 text-center text-xs text-white/70">© {new Date().getFullYear()} Contadores EIRL · Todos los derechos reservados</footer>
    </div>
  )
}
