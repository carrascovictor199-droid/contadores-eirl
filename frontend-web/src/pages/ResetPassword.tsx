import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { Estado } from '../components/Shell'

export default function ResetPassword() {
  const nav = useNavigate()
  const [clave, setClave] = useState(''); const [error, setError] = useState(''); const [ok, setOk] = useState('')
  async function guardar(e: FormEvent) {
    e.preventDefault(); setError('')
    if (!/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/.test(clave)) return setError('Mínimo 8 caracteres con mayúscula, minúscula y número.')
    const { error: err } = await supabase.auth.updateUser({ password: clave })
    if (err) setError('El enlace expiró o no es válido.'); else { setOk('Contraseña actualizada.'); setTimeout(() => nav('/login'), 1200) }
  }
  return (
    <div className="grid min-h-screen place-items-center bg-navy p-4">
      <form onSubmit={guardar} className="card w-full max-w-sm space-y-3">
        <h1 className="text-xl">Nueva contraseña</h1>
        <input className="input" type="password" value={clave} onChange={e => setClave(e.target.value)} />
        <Estado error={error} ok={ok} /><button className="btn w-full">Guardar</button>
      </form>
    </div>
  )
}
