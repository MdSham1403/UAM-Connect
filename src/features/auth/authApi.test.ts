import { describe, expect, it } from 'vitest'
import {
  authError,
  createFakeClient,
  makeSession,
} from '../../test/fakeSupabase'
import {
  parseOtpType,
  requestPasswordReset,
  signIn,
  signOutSafely,
  signUp,
  updatePassword,
  verifyEmailToken,
} from './authApi'

describe('signIn (mocked client)', () => {
  it('succeeds', async () => {
    const f = createFakeClient()
    expect(await signIn(f.client, 'a@b.co', 'pw')).toEqual({ ok: true })
    expect(f.auth.signInWithPassword).toHaveBeenCalledWith({
      email: 'a@b.co',
      password: 'pw',
    })
  })
  it('gives one generic message for bad credentials', async () => {
    const f = createFakeClient()
    f.auth.signInWithPassword.mockResolvedValueOnce({
      data: {},
      error: authError('invalid_credentials', 400),
    } as never)
    expect(await signIn(f.client, 'a@b.co', 'pw')).toEqual({
      ok: false,
      message: 'Invalid email or password.',
    })
  })
  it('explains an unconfirmed email', async () => {
    const f = createFakeClient()
    f.auth.signInWithPassword.mockResolvedValueOnce({
      data: {},
      error: authError('email_not_confirmed'),
    } as never)
    const r = await signIn(f.client, 'a@b.co', 'pw')
    expect(r.ok === false && r.message).toMatch(/confirm your email/i)
  })
  it('reports rate limiting and network failure, including thrown errors', async () => {
    const f = createFakeClient()
    f.auth.signInWithPassword.mockResolvedValueOnce({
      data: {},
      error: authError('over_request_rate_limit', 429),
    } as never)
    expect(await signIn(f.client, 'a', 'b')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/too many/i),
    })
    f.auth.signInWithPassword.mockResolvedValueOnce({
      data: {},
      error: authError('', 0, 'AuthRetryableFetchError'),
    } as never)
    expect(await signIn(f.client, 'a', 'b')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/reach the server/i),
    })
    f.auth.signInWithPassword.mockRejectedValueOnce(new Error('boom'))
    expect(await signIn(f.client, 'a', 'b')).toMatchObject({ ok: false })
  })
})

describe('signUp (mocked client)', () => {
  it('sends the redirect and reports success without a session', async () => {
    const f = createFakeClient()
    expect(
      await signUp(
        f.client,
        'a@b.co',
        'Password1234',
        'http://x/?flow=confirm',
      ),
    ).toEqual({ ok: true })
    expect(f.auth.signUp).toHaveBeenCalledWith({
      email: 'a@b.co',
      password: 'Password1234',
      options: { emailRedirectTo: 'http://x/?flow=confirm' },
    })
  })
  it('looks identical for an already-registered address (no enumeration)', async () => {
    const f = createFakeClient()
    f.auth.signUp.mockResolvedValueOnce({
      data: { user: { id: 'x', identities: [] }, session: null },
      error: null,
    } as never)
    expect(await signUp(f.client, 'a@b.co', 'Password1234', 'r')).toEqual({
      ok: true,
    })
  })
  it('refuses and clears a session returned at sign-up (confirmation not enforced)', async () => {
    const f = createFakeClient()
    f.auth.signUp.mockResolvedValueOnce({
      data: { user: { id: 'x' }, session: makeSession() },
      error: null,
    } as never)
    const r = await signUp(f.client, 'a@b.co', 'Password1234', 'r')
    expect(r.ok).toBe(false)
    expect(f.auth.signOut).toHaveBeenCalledWith({ scope: 'local' })
  })
  it('maps weak-password and rate-limit errors', async () => {
    const f = createFakeClient()
    f.auth.signUp.mockResolvedValueOnce({
      data: {},
      error: authError('weak_password'),
    } as never)
    expect(await signUp(f.client, 'a', 'b', 'r')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/requirements/i),
    })
    f.auth.signUp.mockResolvedValueOnce({
      data: {},
      error: authError('over_email_send_rate_limit', 429),
    } as never)
    expect(await signUp(f.client, 'a', 'b', 'r')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/too many/i),
    })
  })
})

describe('requestPasswordReset (mocked client)', () => {
  it('reports success even when the server errors for an unknown address', async () => {
    const f = createFakeClient()
    f.auth.resetPasswordForEmail.mockResolvedValueOnce({
      data: {},
      error: authError('user_not_found', 404),
    } as never)
    expect(await requestPasswordReset(f.client, 'a@b.co', 'r')).toEqual({
      ok: true,
    })
  })
  it('still surfaces rate limiting', async () => {
    const f = createFakeClient()
    f.auth.resetPasswordForEmail.mockResolvedValueOnce({
      data: {},
      error: authError('over_email_send_rate_limit', 429),
    } as never)
    expect(await requestPasswordReset(f.client, 'a@b.co', 'r')).toMatchObject({
      ok: false,
    })
  })
})

describe('updatePassword (mocked client)', () => {
  it('succeeds and maps common failures', async () => {
    const f = createFakeClient()
    expect(await updatePassword(f.client, 'NewPassword123')).toEqual({
      ok: true,
    })
    f.auth.updateUser.mockResolvedValueOnce({
      data: {},
      error: authError('same_password'),
    } as never)
    expect(await updatePassword(f.client, 'x')).toMatchObject({
      message: expect.stringMatching(/not used before/i),
    })
    f.auth.updateUser.mockResolvedValueOnce({
      data: {},
      error: authError('', 400, 'AuthSessionMissingError'),
    } as never)
    expect(await updatePassword(f.client, 'x')).toMatchObject({
      message: expect.stringMatching(/expired/i),
    })
  })
})

describe('signOutSafely (mocked client)', () => {
  it('revokes on the server when it can', async () => {
    const f = createFakeClient()
    expect(await signOutSafely(f.client)).toEqual({
      ok: true,
      serverRevoked: true,
    })
    expect(f.auth.signOut).toHaveBeenCalledTimes(1)
  })
  it('falls back to a local sign-out when the server call fails or throws', async () => {
    const f = createFakeClient()
    f.auth.signOut.mockResolvedValueOnce({
      error: authError('', 0, 'AuthRetryableFetchError'),
    } as never)
    expect(await signOutSafely(f.client)).toEqual({
      ok: true,
      serverRevoked: false,
    })
    expect(f.auth.signOut).toHaveBeenLastCalledWith({ scope: 'local' })
    const g = createFakeClient()
    g.auth.signOut.mockRejectedValueOnce(new Error('offline'))
    expect(await signOutSafely(g.client)).toEqual({
      ok: true,
      serverRevoked: false,
    })
    expect(g.auth.signOut).toHaveBeenLastCalledWith({ scope: 'local' })
  })
})

describe('email token links (mocked client)', () => {
  it('only accepts known token types', () => {
    expect(parseOtpType('recovery')).toBe('recovery')
    expect(parseOtpType('signup')).toBe('signup')
    expect(parseOtpType('magiclink')).toBeNull()
    expect(parseOtpType(null)).toBeNull()
  })
  it('verifies a token and reports a safe message on failure', async () => {
    const f = createFakeClient()
    expect(await verifyEmailToken(f.client, 'hash', 'email')).toEqual({
      ok: true,
    })
    expect(f.auth.verifyOtp).toHaveBeenCalledWith({
      token_hash: 'hash',
      type: 'email',
    })
    f.auth.verifyOtp.mockResolvedValueOnce({
      data: {},
      error: authError('otp_expired'),
    } as never)
    expect(await verifyEmailToken(f.client, 'hash', 'email')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/invalid or has expired/i),
    })
  })
})
