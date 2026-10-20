import type { SupabaseClient } from '@supabase/supabase-js'

export type Assurance =
  { ok: true; level: 'aal1' | 'aal2' | null } | { ok: false; message: string }
export type TotpFactors =
  { ok: true; verifiedFactorId: string | null } | { ok: false; message: string }
export type Enrollment =
  | { ok: true; factorId: string; qrCode: string; secret: string }
  | { ok: false; message: string }

const FAILED = 'Could not reach the server. Try again.'

/** Current authentication assurance level of the session (aal2 = authenticator code verified). */
export async function getAssurance(client: SupabaseClient): Promise<Assurance> {
  try {
    const { data, error } =
      await client.auth.mfa.getAuthenticatorAssuranceLevel()
    if (error) return { ok: false, message: FAILED }
    return {
      ok: true,
      level: (data?.currentLevel as 'aal1' | 'aal2' | null) ?? null,
    }
  } catch {
    return { ok: false, message: FAILED }
  }
}

export async function findVerifiedTotpFactor(
  client: SupabaseClient,
): Promise<TotpFactors> {
  try {
    const { data, error } = await client.auth.mfa.listFactors()
    if (error) return { ok: false, message: FAILED }
    // `totp` lists verified TOTP factors only.
    return { ok: true, verifiedFactorId: data?.totp?.[0]?.id ?? null }
  } catch {
    return { ok: false, message: FAILED }
  }
}

export async function enrollTotp(client: SupabaseClient): Promise<Enrollment> {
  try {
    const { data, error } = await client.auth.mfa.enroll({
      factorType: 'totp',
      friendlyName: `UAM Connect ${Date.now()}`,
    })
    if (error || !data)
      return {
        ok: false,
        message: 'Could not start authenticator setup. Try again.',
      }
    return {
      ok: true,
      factorId: data.id,
      qrCode: data.totp.qr_code,
      secret: data.totp.secret,
    }
  } catch {
    return { ok: false, message: FAILED }
  }
}

export async function verifyTotp(
  client: SupabaseClient,
  factorId: string,
  code: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  try {
    const { error } = await client.auth.mfa.challengeAndVerify({
      factorId,
      code,
    })
    if (error)
      return {
        ok: false,
        message:
          'That code was not accepted. Check your authenticator app and try again.',
      }
    return { ok: true }
  } catch {
    return { ok: false, message: FAILED }
  }
}
