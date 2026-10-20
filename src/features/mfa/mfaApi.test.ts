import { describe, expect, it } from 'vitest'
import { createFakeClient } from '../../test/fakeSupabase'
import {
  enrollTotp,
  findVerifiedTotpFactor,
  getAssurance,
  verifyTotp,
} from './mfaApi'

describe('mfaApi (mocked client)', () => {
  it('reads the assurance level and reports failures safely', async () => {
    const f = createFakeClient()
    expect(await getAssurance(f.client)).toEqual({ ok: true, level: 'aal1' })
    f.auth.mfa.getAuthenticatorAssuranceLevel.mockResolvedValueOnce({
      data: null,
      error: new Error('x'),
    } as never)
    expect(await getAssurance(f.client)).toMatchObject({ ok: false })
  })
  it('finds a verified TOTP factor or none', async () => {
    const f = createFakeClient()
    expect(await findVerifiedTotpFactor(f.client)).toEqual({
      ok: true,
      verifiedFactorId: null,
    })
    f.auth.mfa.listFactors.mockResolvedValueOnce({
      data: { all: [], totp: [{ id: 'f9' }] },
      error: null,
    } as never)
    expect(await findVerifiedTotpFactor(f.client)).toEqual({
      ok: true,
      verifiedFactorId: 'f9',
    })
  })
  it('enrols a TOTP factor with a unique friendly name and returns the QR and key', async () => {
    const f = createFakeClient()
    const r = await enrollTotp(f.client)
    expect(r).toMatchObject({
      ok: true,
      factorId: 'factor-1',
      secret: 'SECRETKEY',
    })
    expect(f.auth.mfa.enroll).toHaveBeenCalledWith({
      factorType: 'totp',
      friendlyName: expect.stringMatching(/^UAM Connect \d+$/),
    })
  })
  it('verifies a code against a factor and gives a safe message on failure', async () => {
    const f = createFakeClient()
    expect(await verifyTotp(f.client, 'f1', '123456')).toEqual({ ok: true })
    expect(f.auth.mfa.challengeAndVerify).toHaveBeenCalledWith({
      factorId: 'f1',
      code: '123456',
    })
    f.auth.mfa.challengeAndVerify.mockResolvedValueOnce({
      data: null,
      error: { message: 'Invalid TOTP code entered' },
    } as never)
    const bad = await verifyTotp(f.client, 'f1', '000000')
    expect(bad.ok === false && bad.message).toMatch(/not accepted/i)
    expect(bad.ok === false && bad.message).not.toMatch(/invalid totp/i)
  })
})
