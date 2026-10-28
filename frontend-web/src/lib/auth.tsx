import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'

export type Rol = 'ADMINISTRADOR' | 'CONTADOR' | 'ASISTENTE' | 'CLIENTE'
interface Ctx { session: Session | null; roles: Rol[]; loading: boolean; isStaff: boolean; isAdmin: boolean; signOut: () => Promise<void> }
const AuthCtx = createContext<Ctx>({ session: null, roles: [], loading: true, isStaff: false, isAdmin: false, signOut: async () => {} })
export const useAuth = () => useContext(AuthCtx)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [roles, setRoles] = useState<Rol[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); if (!data.session) setLoading(false) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { setSession(s); if (!s) { setRoles([]); setLoading(false) } })
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) return
    setLoading(true)
    supabase.from('user_roles').select('roles(codigo)').eq('user_id', session.user.id).then(({ data }) => {
      const r = (data ?? []).map((x: any) => x.roles?.codigo as Rol).filter(Boolean)
      setRoles(r); setLoading(false)
    })
  }, [session])

  const isStaff = roles.some(r => r !== 'CLIENTE')
  const isAdmin = roles.includes('ADMINISTRADOR')
  return <AuthCtx.Provider value={{ session, roles, loading, isStaff, isAdmin, signOut: async () => { await supabase.auth.signOut() } }}>{children}</AuthCtx.Provider>
}
