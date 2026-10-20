import { describe, expect, it } from 'vitest'
import { validateSupabaseEnv } from './supabase'

const b64 = (o: object) => btoa(JSON.stringify(o)).replace(/=+$/, '')
const jwt = (role: string) =>
  `${b64({ alg: 'HS256' })}.${b64({ role })}.signature`

describe('validateSupabaseEnv', () => {
  it('reports missing configuration', () => {
    expect(validateSupabaseEnv(undefined, undefined)).toMatchObject({
      ok: false,
    })
    expect(validateSupabaseEnv('https://x.supabase.co', '')).toMatchObject({
      ok: false,
    })
  })
  it('rejects invalid and insecure URLs, but allows http on localhost', () => {
    expect(validateSupabaseEnv('not a url', 'k')).toMatchObject({ ok: false })
    expect(validateSupabaseEnv('http://example.com', 'k')).toMatchObject({
      ok: false,
    })
    expect(validateSupabaseEnv('http://localhost:54321', jwt('anon'))).toEqual({
      ok: true,
    })
  })
  it('refuses privileged keys so they cannot reach the browser', () => {
    expect(
      validateSupabaseEnv('https://x.supabase.co', 'sb_secret_abc'),
    ).toMatchObject({ ok: false })
    expect(
      validateSupabaseEnv('https://x.supabase.co', jwt('service_role')),
    ).toMatchObject({ ok: false })
  })
  it('accepts a public anon JWT and a publishable key', () => {
    expect(validateSupabaseEnv('https://x.supabase.co', jwt('anon'))).toEqual({
      ok: true,
    })
    expect(
      validateSupabaseEnv('https://x.supabase.co', 'sb_publishable_abc'),
    ).toEqual({ ok: true })
  })
})
