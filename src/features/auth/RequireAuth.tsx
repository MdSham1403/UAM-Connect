import type { ReactNode } from 'react'
import { useAuth } from './AuthProvider'
import { AuthScreen } from './AuthScreen'
import { ResetPasswordScreen } from './ResetPasswordScreen'

/**
 * UI gate only: it decides what to render. It is NOT an access control. Data protection is
 * enforced by Row Level Security in the database. Being signed in does not mean being a
 * team member.
 */
export function RequireAuth({ children }: { children: ReactNode }) {
  const { status } = useAuth()
  if (status === 'loading') {
    return (
      <main className="flex min-h-dvh items-center justify-center p-6">
        <p role="status" className="text-gray-600">
          Loading…
        </p>
      </main>
    )
  }
  if (status === 'recovery') return <ResetPasswordScreen />
  if (status === 'unauthenticated') return <AuthScreen />
  return <>{children}</>
}
