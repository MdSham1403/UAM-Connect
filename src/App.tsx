import { AccountScreen } from './features/auth/AccountScreen'
import { AuthProvider } from './features/auth/AuthProvider'
import { RequireAuth } from './features/auth/RequireAuth'
import { MembershipGate } from './features/membership/MembershipGate'
import { getSupabase } from './lib/supabase'

export default function App() {
  const setup = getSupabase()
  if (!setup.ok) {
    return (
      <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-2 p-6">
        <h1 className="text-2xl font-semibold">UAM Connect</h1>
        <p role="alert" className="text-red-700">
          {setup.message}
        </p>
      </main>
    )
  }
  return (
    <AuthProvider client={setup.client}>
      <RequireAuth>
        <AccountScreen>
          <MembershipGate />
        </AccountScreen>
      </RequireAuth>
    </AuthProvider>
  )
}
