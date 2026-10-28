import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { api, supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/auth'
import { Estado, Vacio } from '../Shell'

type Row = Record<string, any>
const ROLES = ['ADMINISTRADOR', 'CONTADOR', 'ASISTENTE', 'CLIENTE']
const PERMISOS: [string, string[]][] = [
  ['Clientes', ['Todo', 'Crear/editar', 'Solo ver', 'Solo el suyo']], ['Servicios', ['Todo', 'Todo', 'Solo ver', 'Los suyos']],
  ['Leads', ['Todo', 'Gestionar y convertir', 'Ver y cambiar estado', '—']], ['Solicitudes', ['Todo', 'Responder', 'Solo ver', 'Crear/cancelar las suyas']],
  ['Reportes y actividad', ['Sí', 'Sí', '—', '—']], ['Usuarios y roles', ['Sí', '—', '—', '—']]
]

export default function Usuarios() {
  const { session } = useAuth()
  const [users, setUsers] = useState<Row[]>([]); const [msg, setMsg] = useState({ error: '', ok: '' })
  const [nu, setNu] = useState({ correo: '', password: '', nombreCompleto: '', rol: 'CONTADOR' })
  const cargar = useCallback(async () => {
    const { data } = await supabase.from('profiles').select('id,nombre_completo,correo,activo,user_roles(roles(codigo))').order('created_at', { ascending: false })
    setUsers(data ?? [])
  }, [])
  useEffect(() => { cargar() }, [cargar])
  const aviso = (error = '', ok = '') => setMsg({ error, ok })
  const rolDe = (u: Row) => u.user_roles?.[0]?.roles?.codigo ?? '—'

  async function crear(e: FormEvent) {
    e.preventDefault(); aviso()
    try { await api('/admin/users', { method: 'POST', body: JSON.stringify(nu) }); aviso('', 'Usuario creado.'); setNu({ correo: '', password: '', nombreCompleto: '', rol: 'CONTADOR' }); cargar() }
    catch (er) { aviso((er as Error).message) }
  }
  async function cambiarRol(u: Row, rol: string) {
    try { await api(`/admin/users/${u.id}/rol`, { method: 'PATCH', body: JSON.stringify({ rol }) }); aviso('', 'Rol actualizado.'); cargar() } catch (er) { aviso((er as Error).message) }
  }
  async function activar(u: Row) {
    try { await api(`/admin/users/${u.id}/activo`, { method: 'PATCH', body: JSON.stringify({ activo: !u.activo }) }); aviso('', u.activo ? 'Usuario desactivado.' : 'Usuario activado.'); cargar() } catch (er) { aviso((er as Error).message) }
  }

  return (
    <div className="space-y-4">
      <Estado error={msg.error} ok={msg.ok} />
      <form onSubmit={crear} className="card grid gap-3 sm:grid-cols-5"><h3 className="sm:col-span-5">Crear usuario</h3>
        <input className="input" required placeholder="Nombre completo" value={nu.nombreCompleto} onChange={e => setNu({ ...nu, nombreCompleto: e.target.value })} />
        <input className="input" required type="email" placeholder="Correo" value={nu.correo} onChange={e => setNu({ ...nu, correo: e.target.value })} />
        <input className="input" required type="password" placeholder="Contraseña inicial" value={nu.password} onChange={e => setNu({ ...nu, password: e.target.value })} />
        <select className="input" value={nu.rol} onChange={e => setNu({ ...nu, rol: e.target.value })}>{ROLES.map(r => <option key={r}>{r}</option>)}</select><button className="btn">Crear</button></form>
      {users.length === 0 ? <Vacio /> : (
        <div className="card overflow-x-auto !p-0"><table className="w-full text-sm"><thead className="bg-slate-100 text-left"><tr><th className="p-2">Nombre</th><th>Correo</th><th>Rol</th><th>Estado</th><th /></tr></thead>
          <tbody>{users.map(u => { const yo = u.id === session?.user.id; return (
            <tr key={u.id} className="border-t"><td className="p-2">{u.nombre_completo}</td><td>{u.correo}</td>
              <td><select className="input !w-auto !py-1" disabled={yo} value={rolDe(u)} onChange={e => cambiarRol(u, e.target.value)}>{ROLES.map(r => <option key={r}>{r}</option>)}</select></td>
              <td>{u.activo ? 'Activo' : 'Inactivo'}</td><td><button className="btn btn-ghost !py-1" disabled={yo} onClick={() => activar(u)}>{u.activo ? 'Desactivar' : 'Activar'}</button></td></tr>) })}</tbody></table></div>)}
      <div className="card overflow-x-auto"><h3 className="mb-2">Permisos por rol</h3>
        <table className="w-full text-xs"><thead className="text-left"><tr><th className="p-1">Recurso</th>{ROLES.map(r => <th key={r}>{r}</th>)}</tr></thead>
          <tbody>{PERMISOS.map(([rec, vals]) => <tr key={rec} className="border-t"><td className="p-1 font-medium">{rec}</td>{vals.map((v, i) => <td key={i}>{v}</td>)}</tr>)}</tbody></table>
        <p className="mt-2 text-xs text-slate-500">Los permisos los aplican las políticas RLS de Supabase (no solo la interfaz).</p></div>
    </div>
  )
}
