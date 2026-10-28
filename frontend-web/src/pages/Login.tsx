import { useEffect, useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Estado } from '../components/Shell'

export default function Login() {
  const { session, loading, isStaff } = useAuth()
  const nav = useNavigate()
  const [correo, setCorreo] = useState(''); const [clave, setClave] = useState('')
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [ok, setOk] = useState('')

  useEffect(() => { if (session && !loading) nav(isStaff ? '/panel' : '/cliente', { replace: true }) }, [session, loading, isStaff, nav])

  async function entrar(e: FormEvent) {
    e.preventDefault(); setError(''); setOk(''); setBusy(true)
    const { error: err } = await supabase.auth.signInWithPassword({ email: correo.trim(), password: clave })
    setBusy(false)
    if (err) setError('Correo o contraseña incorrectos.')
  }
  async function recuperar() {
    setError(''); setOk('')
    if (!correo) return setError('Escribe tu correo para recuperar la contraseña.')
    const { error: err } = await supabase.auth.resetPasswordForEmail(correo.trim(), { redirectTo: `${location.origin}/restablecer-contrasena` })
    if (err) setError('No se pudo enviar el correo.'); else setOk('Si el correo existe, recibirás un enlace para restablecer tu contraseña.')
  }
  return (
    <div className="grid min-h-screen place-items-center bg-navy p-4">
      <form onSubmit={entrar} className="card w-full max-w-sm space-y-3">
        <h1 className="text-center text-2xl">Contadores <span className="text-gold">EIRL</span></h1>
        <div><label className="label">Correo</label><input className="input" type="email" required value={correo} onChange={e => setCorreo(e.target.value)} /></div>
        <div><label className="label">Contraseña</label><input className="input" type="password" required value={clave} onChange={e => setClave(e.target.value)} /></div>
        <Estado error={error} ok={ok} />
        <button className="btn w-full" disabled={busy}>{busy ? 'Ingresando…' : 'Iniciar sesión'}</button>
        <button type="button" className="w-full text-xs text-navy underline" onClick={recuperar}>Olvidé mi contraseña</button>
        <p className="text-center text-sm">¿No tienes cuenta? <Link to="/registro" className="font-medium text-navy underline">Crear cuenta</Link></p>
        <Link to="/" className="block text-center text-xs text-slate-500">← Volver al inicio</Link>
      </form>
    </div>
  )
}
