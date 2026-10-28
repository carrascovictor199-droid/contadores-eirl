import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { API_BASE } from '../lib/supabase'
import { validarCorreo, validarRuc, validarTelefono } from '../lib/validators'
import { Estado } from '../components/Shell'

const CLAVE_OK = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/

type DatosSunat = { razonSocial: string; nombreComercial: string; direccion: string; estado: string; condicion: string }

export default function Registro() {
  const [f, setF] = useState({ ruc: '', nombre: '', telefono: '', correo: '', clave: '', clave2: '' })
  const [sunat, setSunat] = useState<DatosSunat | null>(null)
  const [rucMsg, setRucMsg] = useState(''); const [consultando, setConsultando] = useState(false)
  const [error, setError] = useState(''); const [enviado, setEnviado] = useState(false); const [busy, setBusy] = useState(false)
  const set = (k: string, v: string) => setF(x => ({ ...x, [k]: v }))

  // Al completar un RUC válido se consulta SUNAT y se rellenan los datos de la empresa.
  useEffect(() => {
    setSunat(null); setRucMsg('')
    if (f.ruc.length < 11) return
    if (!validarRuc(f.ruc)) return setRucMsg('RUC no válido.')
    let vigente = true
    setConsultando(true)
    fetch(`${API_BASE}/public/ruc/${f.ruc}`)
      .then(async r => {
        const b = await r.json().catch(() => ({}))
        if (!vigente) return
        if (!r.ok) return setRucMsg((b as { message?: string }).message ?? 'No se pudo consultar el RUC.')
        setSunat(b as DatosSunat)
      })
      .catch(() => { if (vigente) setRucMsg('No pudimos consultar el RUC. Inténtalo en unos minutos.') })
      .finally(() => { if (vigente) setConsultando(false) })
    return () => { vigente = false }
  }, [f.ruc])

  async function crear(e: FormEvent) {
    e.preventDefault(); setError('')
    if (!validarRuc(f.ruc)) return setError('Ingresa un RUC válido de 11 dígitos.')
    if (!sunat) return setError('Tu RUC debe existir en SUNAT para crear la cuenta.')
    if (f.nombre.trim().length < 2) return setError('Ingresa tu nombre completo.')
    if (!validarTelefono(f.telefono)) return setError('Teléfono no válido.')
    if (!validarCorreo(f.correo)) return setError('Correo no válido.')
    if (!CLAVE_OK.test(f.clave)) return setError('La contraseña necesita mínimo 8 caracteres, con mayúscula, minúscula y número.')
    if (f.clave !== f.clave2) return setError('Las contraseñas no coinciden.')
    setBusy(true)
    try {
      const r = await fetch(`${API_BASE}/public/registro`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ruc: f.ruc, nombre: f.nombre.trim(), telefono: f.telefono.trim(), correo: f.correo.trim(), password: f.clave })
      })
      const b = await r.json().catch(() => ({})) as { message?: string }
      if (!r.ok) setError(b.message ?? 'No se pudo crear la cuenta. Revisa los datos e inténtalo de nuevo.')
      else setEnviado(true)
    } catch {
      setError('No pudimos conectar con el servidor. Inténtalo en unos minutos.')
    } finally { setBusy(false) }
  }

  return (
    <div className="grid min-h-screen place-items-center bg-navy p-4">
      <div className="card w-full max-w-xl">
        <h1 className="text-center text-2xl">Crear cuenta</h1>
        {enviado ? (
          <div className="space-y-3 py-6 text-center">
            <div className="text-5xl">📧</div>
            <p className="font-medium">Revisa tu correo</p>
            <p className="text-sm text-slate-600">Te enviamos un enlace para confirmar tu cuenta. Al confirmarlo e iniciar sesión, tu portal quedará creado con los datos de tu empresa; el estudio los verificará.</p>
            <Link to="/login" className="btn">Ir a iniciar sesión</Link>
          </div>
        ) : (
          <form onSubmit={crear} className="mt-4 grid gap-3 sm:grid-cols-2">
            <div className="sm:col-span-2">
              <label className="label">RUC de tu empresa *</label>
              <input className="input" inputMode="numeric" maxLength={11} value={f.ruc} onChange={e => set('ruc', e.target.value.replace(/\D/g, ''))} />
              {consultando && <p className="mt-1 text-xs text-slate-500">Consultando SUNAT…</p>}
              {rucMsg && <p className="mt-1 text-xs text-red-600">{rucMsg}</p>}
            </div>
            <div className="sm:col-span-2"><label className="label">Razón social (SUNAT)</label><input className="input bg-slate-100" readOnly value={sunat?.razonSocial ?? ''} placeholder="Se completa al escribir tu RUC" /></div>
            <div><label className="label">Nombre comercial (SUNAT)</label><input className="input bg-slate-100" readOnly value={sunat?.nombreComercial ?? ''} /></div>
            <div><label className="label">Dirección fiscal (SUNAT)</label><input className="input bg-slate-100" readOnly value={sunat?.direccion ?? ''} /></div>
            <div><label className="label">Tu nombre completo *</label><input className="input" autoComplete="name" value={f.nombre} onChange={e => set('nombre', e.target.value)} /></div>
            <div><label className="label">Teléfono *</label><input className="input" autoComplete="tel" value={f.telefono} onChange={e => set('telefono', e.target.value)} /></div>
            <div className="sm:col-span-2"><label className="label">Correo electrónico *</label><input className="input" type="email" autoComplete="email" value={f.correo} onChange={e => set('correo', e.target.value)} /></div>
            <div><label className="label">Contraseña *</label><input className="input" type="password" autoComplete="new-password" value={f.clave} onChange={e => set('clave', e.target.value)} /></div>
            <div><label className="label">Repetir contraseña *</label><input className="input" type="password" autoComplete="new-password" value={f.clave2} onChange={e => set('clave2', e.target.value)} /></div>
            <div className="sm:col-span-2"><Estado error={error} /><button className="btn btn-gold w-full" disabled={busy || !sunat}>{busy ? 'Creando cuenta…' : 'Crear cuenta'}</button></div>
            <p className="text-center text-xs text-slate-500 sm:col-span-2">¿Ya tienes cuenta? <Link to="/login" className="text-navy underline">Iniciar sesión</Link></p>
          </form>
        )}
      </div>
    </div>
  )
}
