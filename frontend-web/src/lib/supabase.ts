import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string
if (!url || !anon) console.error('Falta configurar VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY en .env')

// Solo credenciales públicas (anon). La seguridad real la imponen las políticas RLS.
export const supabase = createClient(url, anon, {
  auth: { persistSession: true, autoRefreshToken: true }
})

export const API_BASE = (import.meta.env.VITE_API_BASE_URL as string) || 'http://localhost:8080/api'

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const { data } = await supabase.auth.getSession()
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.session?.access_token ?? ''}`, ...(init.headers ?? {}) }
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((body as { message?: string }).message ?? `Error ${res.status}`)
  return body as T
}
