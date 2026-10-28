import { useState, type FormEvent } from 'react'
import { API_BASE, supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/auth'
import { Estado } from '../Shell'

export default function Configuracion() {
  const { session, roles, signOut } = useAuth()
  const [clave, setClave] = useState(''); const [msg, setMsg] = useState({ error: '', ok: '' }); const [api, setApi] = useState('')
  async function cambiar(e: FormEvent) {
    e.preventDefault()
    if (!/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/.test(clave)) return setMsg({ error: 'Mínimo 8 caracteres con mayúscula, minúscula y número.', ok: '' })
    const { error } = await supabase.auth.updateUser({ password: clave })
    setMsg(error ? { error: 'No se pudo cambiar la contraseña.', ok: '' } : { error: '', ok: 'Contraseña actualizada.' }); setClave('')
  }
  async function probar() {
    setApi('Probando…')
    try { const r = await fetch(`${API_BASE}/health`); setApi(r.ok ? 'Backend disponible ✔' : `Backend respondió ${r.status}`) } catch { setApi('Backend no disponible ✘') }
  }
  return (
    <div className="grid max-w-xl gap-4">
      <div className="card text-sm"><p><b>Usuario:</b> {session?.user.email}</p><p><b>Rol:</b> {roles.join(', ')}</p><p><b>Supabase:</b> {String(import.meta.env.VITE_SUPABASE_URL)}</p><p><b>API:</b> {API_BASE}</p>
        <div className="mt-2 flex items-center gap-3"><button className="btn btn-ghost" onClick={probar}>Probar backend</button><span>{api}</span></div></div>
      <form onSubmit={cambiar} className="card space-y-2"><h3>Cambiar contraseña</h3><input className="input" type="password" value={clave} onChange={e => setClave(e.target.value)} /><Estado error={msg.error} ok={msg.ok} /><button className="btn">Guardar</button></form>
      <button className="btn btn-gold" onClick={signOut}>Cerrar sesión</button>
    </div>
  )
}
