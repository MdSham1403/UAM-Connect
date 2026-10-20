import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import type { Session, SupabaseClient, User } from '@supabase/supabase-js'
import { signOutSafely, verifyEmailToken } from './authApi'
import { cleanUrl, readUrlFlow } from './flow'

export type AuthStatus =
  'loading' | 'unauthenticated' | 'authenticated' | 'recovery'

interface AuthContextValue {
  client: SupabaseClient
  status: AuthStatus
  session: Session | null
  user: User | null
  /** One-line message to show on the sign-in screen (expired session, bad link, ...). */
  notice: string | null
  clearNotice: () => void
  signOut: () => Promise<{ serverRevoked: boolean }>
  /** Called after the user finishes (or abandons) the password reset form. */
  endRecovery: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}

const SESSION_ENDED = 'Your session has ended. Sign in again.'

export function AuthProvider({
  client,
  children,
}: {
  client: SupabaseClient
  children: ReactNode
}) {
  const [status, setStatus] = useState<AuthStatus>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const recoveryRef = useRef(false)
  const userInitiatedSignOut = useRef(false)
  const sessionRef = useRef<Session | null>(null)

  useEffect(() => {
    let active = true
    const initial = readUrlFlow()
    recoveryRef.current =
      initial.flow === 'recovery' && initial.errorMessage === null

    // Do not call other Supabase methods inside this callback (the client holds a lock while
    // it runs); only record state.
    const { data } = client.auth.onAuthStateChange((event, next) => {
      if (!active) return
      if (event === 'PASSWORD_RECOVERY') recoveryRef.current = true
      if (event === 'SIGNED_OUT' || !next) {
        // An unexpected sign-out (refresh failure, revoked session, another tab) gets a notice;
        // a sign-out the user asked for does not.
        if (sessionRef.current && !userInitiatedSignOut.current)
          setNotice(SESSION_ENDED)
        recoveryRef.current = false
        sessionRef.current = null
        setSession(null)
        setStatus('unauthenticated')
        return
      }
      sessionRef.current = next
      setSession(next)
      setStatus(recoveryRef.current ? 'recovery' : 'authenticated')
    })

    void (async () => {
      try {
        // Cross-device links: ?flow=...&token_hash=...&type=...
        if (initial.tokenHash && initial.otpType) {
          if (initial.otpType === 'recovery') recoveryRef.current = true
          const result = await verifyEmailToken(
            client,
            initial.tokenHash,
            initial.otpType,
          )
          if (!result.ok) {
            recoveryRef.current = false
            if (active) setNotice(result.message)
          }
        } else if (initial.errorMessage) {
          setNotice(initial.errorMessage)
        }
        // getSession() waits for the client's own URL/code handling to finish.
        const { data: current, error } = await client.auth.getSession()
        if (!active) return
        if (error) {
          setNotice('Could not restore your session. Sign in again.')
          setStatus('unauthenticated')
        } else if (current.session) {
          sessionRef.current = current.session
          setSession(current.session)
          setStatus(recoveryRef.current ? 'recovery' : 'authenticated')
        } else {
          setStatus('unauthenticated')
        }
      } catch {
        if (active) {
          setNotice('Could not restore your session. Sign in again.')
          setStatus('unauthenticated')
        }
      } finally {
        cleanUrl()
      }
    })()

    return () => {
      active = false
      data.subscription.unsubscribe()
    }
  }, [client])

  const signOut = useCallback(async () => {
    userInitiatedSignOut.current = true
    const result = await signOutSafely(client)
    // Reset local state even if no SIGNED_OUT event arrives.
    recoveryRef.current = false
    sessionRef.current = null
    setSession(null)
    setStatus('unauthenticated')
    userInitiatedSignOut.current = false
    return { serverRevoked: result.serverRevoked }
  }, [client])

  const endRecovery = useCallback(() => {
    recoveryRef.current = false
    setStatus(session ? 'authenticated' : 'unauthenticated')
  }, [session])

  const value = useMemo<AuthContextValue>(
    () => ({
      client,
      status,
      session,
      user: session?.user ?? null,
      notice,
      clearNotice: () => setNotice(null),
      signOut,
      endRecovery,
    }),
    [client, status, session, notice, signOut, endRecovery],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
