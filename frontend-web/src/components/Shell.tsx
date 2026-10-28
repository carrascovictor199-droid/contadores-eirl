import type { ReactNode } from 'react'
import { useAuth } from '../lib/auth'

export default function Shell({ titulo, tabs, tab, onTab, children }: { titulo: string; tabs: string[]; tab: string; onTab: (t: string) => void; children: ReactNode }) {
  const { session, signOut } = useAuth()
  return (
    <div className="min-h-screen">
      <header className="bg-navy text-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <span className="font-serif text-xl">Contadores <span className="text-gold">EIRL</span> · {titulo}</span>
          <span className="flex items-center gap-3 text-xs"><span className="hidden sm:inline">{session?.user.email}</span>
            <button className="btn btn-gold" onClick={signOut}>Cerrar sesión</button></span>
        </div>
        <nav className="mx-auto flex max-w-6xl gap-1 overflow-x-auto px-4">
          {tabs.map(t => (
            <button key={t} onClick={() => onTab(t)} className={`whitespace-nowrap px-3 py-2 text-sm ${t === tab ? 'border-b-2 border-gold text-gold' : 'text-white/80 hover:text-white'}`}>{t}</button>
          ))}
        </nav>
      </header>
      <main className="mx-auto max-w-6xl p-4">{children}</main>
    </div>
  )
}

export function Estado({ error, ok }: { error?: string; ok?: string }) {
  if (error) return <p className="my-2 rounded bg-red-50 p-2 text-sm text-red-700">{error}</p>
  if (ok) return <p className="my-2 rounded bg-green-50 p-2 text-sm text-green-700">{ok}</p>
  return null
}
export const Vacio = ({ texto = 'Sin registros.' }: { texto?: string }) => <p className="p-6 text-center text-sm text-slate-500">{texto}</p>
