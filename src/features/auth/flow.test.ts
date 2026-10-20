import { afterEach, describe, expect, it } from 'vitest'
import { cleanUrl, readUrlFlow } from './flow'

afterEach(() => window.history.replaceState({}, '', '/'))

describe('URL flow helpers', () => {
  it('reads our own markers and token links', () => {
    const f = readUrlFlow({
      search: '?flow=recovery&token_hash=abc&type=recovery',
      hash: '',
    })
    expect(f).toMatchObject({
      flow: 'recovery',
      tokenHash: 'abc',
      otpType: 'recovery',
      errorMessage: null,
    })
  })
  it('ignores unknown flows and token types', () => {
    const f = readUrlFlow({ search: '?flow=admin&type=magiclink', hash: '' })
    expect(f).toMatchObject({ flow: null, otpType: null })
  })
  it('replaces link errors (query or hash) with a fixed message, never the raw text', () => {
    const q = readUrlFlow({
      search: '?error=access_denied&error_description=Secret+detail',
      hash: '',
    })
    expect(q.errorMessage).toMatch(/invalid or has expired/i)
    expect(q.errorMessage).not.toMatch(/secret/i)
    expect(
      readUrlFlow({ search: '', hash: '#error_code=otp_expired' }).errorMessage,
    ).not.toBeNull()
  })
  it('removes one-time values from the address bar', () => {
    window.history.replaceState(
      {},
      '',
      '/?flow=confirm&code=secret-code&keep=1#access_token=t',
    )
    cleanUrl()
    expect(window.location.search).toBe('?keep=1')
    expect(window.location.hash).toBe('')
    expect(window.location.href).not.toMatch(/secret-code|access_token/)
  })
})
