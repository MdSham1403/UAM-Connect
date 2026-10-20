import { useState, type ReactNode } from 'react'
import { useAuth } from './AuthProvider'
import { Banner, LinkButton } from './ui'

/** Page shell for signed-in users: who is signed in, sign-out, and the content below. */
export function AccountScreen({ children }: { children: ReactNode }) {
  const { user, signOut } = useAuth()
  const [warning, setWarning] = useState<string | null>(null)

  async function onSignOut() {
    const r = await signOut()
    if (!r.serverRevoked)
      setWarning(
        'Signed out on this device. The server could not be reached to end other sessions.',
      )
  }

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col gap-4 p-6">
      <h1 className="text-2xl font-semibold">UAM Connect</h1>
      <p className="text-sm text-gray-600">
        Signed in as <span className="font-medium">{user?.email}</span>
      </p>
      {warning ? <Banner kind="info">{warning}</Banner> : null}
      {children}
      <LinkButton onClick={() => void onSignOut()}>Sign out</LinkButton>
    </main>
  )
}
