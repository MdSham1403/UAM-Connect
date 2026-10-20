import type { AuthError, SupabaseClient } from '@supabase/supabase-js'

export type ApiResult = { ok: true } | { ok: false; message: string }

const RATE_LIMITED = 'Too many attempts. Wait a few minutes and try again.'
const NETWORK = 'Cannot reach the server. Check your connection and try again.'

function code(error: AuthError | null): string {
  return (error as { code?: string } | null)?.code ?? ''
}
function isRateLimited(error: AuthError): boolean {
  return (
    error.status === 429 ||
    code(error) === 'over_request_rate_limit' ||
    code(error) === 'over_email_send_rate_limit'
  )
}
function isNetwork(error: AuthError): boolean {
  return (
    error.name === 'AuthRetryableFetchError' ||
    error.status === 0 ||
    (error.status === undefined && /fetch/i.test(error.message))
  )
}

export async function signIn(
  client: SupabaseClient,
  email: string,
  password: string,
): Promise<ApiResult> {
  try {
    const { error } = await client.auth.signInWithPassword({ email, password })
    if (!error) return { ok: true }
    if (isRateLimited(error)) return { ok: false, message: RATE_LIMITED }
    if (isNetwork(error)) return { ok: false, message: NETWORK }
    // Only reported by Supabase after the password was verified, so it does not leak existence.
    if (code(error) === 'email_not_confirmed') {
      return {
        ok: false,
        message:
          'Confirm your email address first. Check your inbox for the link.',
      }
    }
    return { ok: false, message: 'Invalid email or password.' }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export const SIGN_UP_NOTICE =
  'If this address can be registered, a confirmation link is on its way. Open it on this device, then sign in.'

export async function signUp(
  client: SupabaseClient,
  email: string,
  password: string,
  redirectTo: string,
): Promise<ApiResult> {
  try {
    const { data, error } = await client.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: redirectTo },
    })
    if (error) {
      if (isRateLimited(error)) return { ok: false, message: RATE_LIMITED }
      if (isNetwork(error)) return { ok: false, message: NETWORK }
      if (code(error) === 'weak_password') {
        return {
          ok: false,
          message:
            'That password does not meet the server requirements. Choose a stronger one.',
        }
      }
      return {
        ok: false,
        message: 'Could not create the account. Try again later.',
      }
    }
    if (data.session) {
      // A session at sign-up means the server is NOT enforcing email confirmation. Refuse it.
      await client.auth.signOut({ scope: 'local' })
      return {
        ok: false,
        message:
          'Email confirmation is not enabled on the server, so sign-up was stopped. Contact the administrator.',
      }
    }
    // Same outcome whether or not the address already exists (no account enumeration).
    return { ok: true }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export const RESET_NOTICE =
  'If an account exists for this address, a reset link is on its way.'

export async function requestPasswordReset(
  client: SupabaseClient,
  email: string,
  redirectTo: string,
): Promise<ApiResult> {
  try {
    const { error } = await client.auth.resetPasswordForEmail(email, {
      redirectTo,
    })
    if (error) {
      if (isRateLimited(error)) return { ok: false, message: RATE_LIMITED }
      if (isNetwork(error)) return { ok: false, message: NETWORK }
      // Any other error is reported as success so the response never reveals account existence.
    }
    return { ok: true }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export async function updatePassword(
  client: SupabaseClient,
  password: string,
): Promise<ApiResult> {
  try {
    const { error } = await client.auth.updateUser({ password })
    if (!error) return { ok: true }
    switch (code(error)) {
      case 'same_password':
        return {
          ok: false,
          message: 'Choose a password you have not used before.',
        }
      case 'weak_password':
        return {
          ok: false,
          message: 'That password does not meet the server requirements.',
        }
      case 'session_not_found':
      case 'session_expired':
      case 'reauthentication_needed':
        return {
          ok: false,
          message: 'Your reset link has expired. Request a new one.',
        }
      default:
        if (isRateLimited(error)) return { ok: false, message: RATE_LIMITED }
        if (isNetwork(error)) return { ok: false, message: NETWORK }
        if (error.name === 'AuthSessionMissingError') {
          return {
            ok: false,
            message: 'Your reset link has expired. Request a new one.',
          }
        }
        return {
          ok: false,
          message: 'Could not update the password. Try again.',
        }
    }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export type SignOutResult = { ok: true; serverRevoked: boolean }

/** Always clears the local session, even when the server call fails. */
export async function signOutSafely(
  client: SupabaseClient,
): Promise<SignOutResult> {
  try {
    const { error } = await client.auth.signOut()
    if (!error) return { ok: true, serverRevoked: true }
  } catch {
    // fall through to local sign-out
  }
  try {
    await client.auth.signOut({ scope: 'local' })
  } catch {
    // nothing more can be done; the provider still resets its own state
  }
  return { ok: true, serverRevoked: false }
}

const OTP_TYPES = ['signup', 'email', 'recovery'] as const
export type OtpFlowType = (typeof OTP_TYPES)[number]

export function parseOtpType(value: string | null): OtpFlowType | null {
  return (OTP_TYPES as readonly string[]).includes(value ?? '')
    ? (value as OtpFlowType)
    : null
}

/** Verify a cross-device confirmation/recovery link of the form ?token_hash=...&type=... */
export async function verifyEmailToken(
  client: SupabaseClient,
  tokenHash: string,
  type: OtpFlowType,
): Promise<ApiResult> {
  try {
    const { error } = await client.auth.verifyOtp({
      token_hash: tokenHash,
      type,
    })
    if (!error) return { ok: true }
    return {
      ok: false,
      message: 'This link is invalid or has expired. Request a new one.',
    }
  } catch {
    return { ok: false, message: NETWORK }
  }
}
