import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Estado, Vacio } from './Shell'

type Row = Record<string, any>
const BUCKET = 'documentos-clientes'
const PERMITIDOS = ['application/pdf', 'image/png', 'image/jpeg', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']

/** Documentos en Supabase Storage (bucket privado, RLS). Con `clientes` el personal elige cliente; con `clienteId` fijo es el portal del cliente. */
export default function Documentos({ clientes, clienteId, puedeBorrar }: { clientes?: Row[]; clienteId?: string; puedeBorrar: boolean }) {
  const { session } = useAuth()
  const [sel, setSel] = useState(clienteId ?? '')
  const [docs, setDocs] = useState<Row[]>([])
  const [msg, setMsg] = useState({ error: '', ok: '' }); const [busy, setBusy] = useState(false)
  const id = clienteId ?? sel

  const cargar = useCallback(async () => {
    if (!id) return setDocs([])
    const { data } = await supabase.from('documentos').select('*').eq('cliente_id', id).order('created_at', { ascending: false })
    setDocs(data ?? [])
  }, [id])
  useEffect(() => { cargar() }, [cargar])

  async function subir(file: File | undefined) {
    if (!file || !id) return
    setMsg({ error: '', ok: '' })
    if (!PERMITIDOS.includes(file.type)) return setMsg({ error: 'Formato no permitido (PDF, PNG, JPG, XLSX o DOCX).', ok: '' })
    if (file.size > 10 * 1024 * 1024) return setMsg({ error: 'El archivo supera 10 MB.', ok: '' })
    setBusy(true)
    const path = `${id}/${Date.now()}-${file.name.replace(/[^\w.-]+/g, '_')}`
    const up = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type })
    if (up.error) { setBusy(false); return setMsg({ error: 'No se pudo subir el archivo.', ok: '' }) }
    const { error } = await supabase.from('documentos').insert({ cliente_id: id, nombre: file.name, storage_path: path, mime_type: file.type, tamano_bytes: file.size, subido_por: session!.user.id })
    if (error) await supabase.storage.from(BUCKET).remove([path])
    setBusy(false); setMsg(error ? { error: 'No se pudo registrar el documento.', ok: '' } : { error: '', ok: 'Documento subido.' }); cargar()
  }
  async function descargar(d: Row) {
    const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(d.storage_path, 60)
    if (error || !data) return setMsg({ error: 'No se pudo generar el enlace.', ok: '' })
    window.open(data.signedUrl, '_blank', 'noopener')
  }
  async function borrar(d: Row) {
    if (!confirm(`¿Eliminar "${d.nombre}"?`)) return
    await supabase.storage.from(BUCKET).remove([d.storage_path])
    const { error } = await supabase.from('documentos').delete().eq('id', d.id)
    setMsg(error ? { error: 'No se pudo eliminar.', ok: '' } : { error: '', ok: 'Documento eliminado.' }); cargar()
  }

  return (
    <div className="space-y-3">
      {clientes && <select className="input max-w-md" value={sel} onChange={e => setSel(e.target.value)}><option value="">Selecciona un cliente…</option>{clientes.map(c => <option key={c.id} value={c.id}>{c.razon_social}</option>)}</select>}
      <Estado error={msg.error} ok={msg.ok} />
      {id && <div className="card"><label className="label">Subir documento (máx. 10 MB)</label><input type="file" disabled={busy} onChange={e => { subir(e.target.files?.[0]); e.target.value = '' }} /></div>}
      {!id ? <Vacio texto="Selecciona un cliente." /> : docs.length === 0 ? <Vacio texto="Sin documentos." /> : (
        <div className="card !p-0">{docs.map(d => (
          <div key={d.id} className="flex items-center justify-between border-b p-3 text-sm last:border-0"><span>{d.nombre}<span className="ml-2 text-xs text-slate-500">{d.created_at.slice(0, 10)} · {Math.round((d.tamano_bytes ?? 0) / 1024)} KB</span></span>
            <span className="flex gap-2"><button className="btn btn-ghost !py-1" onClick={() => descargar(d)}>Descargar</button>{puedeBorrar && <button className="btn btn-ghost !py-1" onClick={() => borrar(d)}>Eliminar</button>}</span></div>))}</div>)}
    </div>
  )
}
