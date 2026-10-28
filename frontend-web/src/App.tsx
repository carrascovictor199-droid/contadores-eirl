import { Navigate, Route, Routes } from 'react-router-dom'
import type { ReactNode } from 'react'
import { useAuth } from './lib/auth'
import Home from './pages/Home'
import Login from './pages/Login'
import Registro from './pages/Registro'
import ResetPassword from './pages/ResetPassword'
import ClientPanel from './pages/ClientPanel'
import StaffPanel from './pages/StaffPanel'

function Protected({ staff, children }: { staff: boolean; children: ReactNode }) {
  const { session, loading, isStaff } = useAuth()
  if (loading) return <p className="p-10 text-center text-slate-500">Cargando…</p>
  if (!session) return <Navigate to="/login" replace />
  if (staff !== isStaff) return <Navigate to={isStaff ? '/panel' : '/cliente'} replace />
  return <>{children}</>
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/login" element={<Login />} />
      <Route path="/registro" element={<Registro />} />
      <Route path="/restablecer-contrasena" element={<ResetPassword />} />
      <Route path="/cliente" element={<Protected staff={false}><ClientPanel /></Protected>} />
      <Route path="/panel" element={<Protected staff><StaffPanel /></Protected>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
