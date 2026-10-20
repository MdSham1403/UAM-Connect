import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export type SupabaseSetup =
  { ok: true; client: SupabaseClient } | { ok: false; message: string }

/** Decode a JWT payload without verifying it (used only to refuse obviously privileged keys). */
function jwtRole(key: string): string | null {
  const parts = key.split('.')
  if (parts.length !== 3) return null
  try {
    const json = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'))
    const role = (JSON.parse(json) as { role?: unknown }).role
    return typeof role === 'string' ? role : null
  } catch {
    return null
  }
}

/**
 * Validate the public Supabase settings. Refuses a service-role or secret key so that a
 * privileged credential can never be shipped to the browser by mistake.
 */
export function validateSupabaseEnv(
  url: unknown,
  key: unknown,
): SupabaseSetup | { ok: true } {
  if (
    typeof url !== 'string' ||
    url.trim() === '' ||
    typeof key !== 'string' ||
    key.trim() === ''
  ) {
    return {
      ok: false,
      message:
        'Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env.local.',
    }
  }
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return { ok: false, message: 'VITE_SUPABASE_URL is not a valid URL.' }
  }
  const local =
    parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1'
  if (parsed.protocol !== 'https:' && !(local && parsed.protocol === 'http:')) {
    return {
      ok: false,
      message:
        'VITE_SUPABASE_URL must use https (http is allowed only for localhost).',
    }
  }
  if (key.startsWith('sb_secret_') || jwtRole(key) === 'service_role') {
    return {
      ok: false,
      message:
        'VITE_SUPABASE_ANON_KEY holds a privileged key. Use the public anon/publishable key only; never expose a service-role or secret key in the browser.',
    }
  }
  return { ok: true }
}

let cached: SupabaseSetup | undefined

/** Create (once) the browser Supabase client from public environment variables. */
export function getSupabase(): SupabaseSetup {
  if (cached) return cached
  const url: unknown = import.meta.env.VITE_SUPABASE_URL
  const key: unknown = import.meta.env.VITE_SUPABASE_ANON_KEY
  const check = validateSupabaseEnv(url, key)
  if (!check.ok) {
    cached = check
    return cached
  }
  cached = {
    ok: true,
    client: createClient(url as string, key as string, {
      auth: {
        flowType: 'pkce',
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    }),
  }
  return cached
}
