import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../lib/auth'
import { Vacio } from '../Shell'

type Row = Record<string, any>
export default function Mensajes({ clientes }: { clientes: Row[] }) {
  const { session } = useAuth()
  const [cli, setCli] = useState(''); const [msgs, setMsgs] = useState<Row[]>([]); const [texto, setTexto] = useState(''); const [error, setError] = useState('')
  const cargar = useCallback(async () => {
    if (!cli) return setMsgs([])
    const { data } = await supabase.from('mensajes').select('*').eq('cliente_id', cli).order('created_at')
    setMsgs(data ?? [])
  }, [cli])
  useEffect(() => { cargar() }, [cargar])
  async function enviar(e: FormEvent) {
    e.preventDefault(); setError('')
    if (!cli || !texto.trim()) return
    const { error: err } = await supabase.from('mensajes').insert({ cliente_id: cli, remitente_id: session!.user.id, contenido: texto.trim() })
    if (err) return setError('No se pudo enviar.')
    setTexto(''); cargar()
  }
  return (
    <div className="space-y-3">
      <select className="input max-w-md" value={cli} onChange={e => setCli(e.target.value)}><option value="">Selecciona un cliente…</option>{clientes.map(c => <option key={c.id} value={c.id}>{c.razon_social}</option>)}</select>
      {!cli ? <Vacio texto="Selecciona un cliente para ver la conversación." /> : (
        <div className="card">
          <div className="max-h-96 space-y-2 overflow-y-auto">{msgs.length === 0 ? <Vacio texto="Sin mensajes." /> : msgs.map(m => (
            <div key={m.id} className={`max-w-[80%] rounded-lg p-2 text-sm ${m.remitente_id === session!.user.id ? 'ml-auto bg-navy text-white' : 'bg-slate-100'}`}>{m.contenido}<div className="text-[10px] opacity-60">{m.created_at.slice(0, 16).replace('T', ' ')}</div></div>))}</div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <form onSubmit={enviar} className="mt-3 flex gap-2"><input className="input" value={texto} onChange={e => setTexto(e.target.value)} placeholder="Escribe un mensaje…" /><button className="btn">Enviar</button></form>
          <p className="mt-2 text-xs text-slate-500">El cliente recibe una notificación automática.</p>
        </div>)}
    </div>
  )
}
