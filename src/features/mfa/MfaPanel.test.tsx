import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { MfaPanel } from './MfaPanel'

const session = makeSession()

describe('MfaPanel (mocked client)', () => {
  it('reports verified immediately when the session is already aal2', async () => {
    const fake = createFakeClient({ session })
    fake.auth.mfa.getAuthenticatorAssuranceLevel.mockResolvedValue({
      data: { currentLevel: 'aal2', nextLevel: 'aal2' },
      error: null,
    } as never)
    const onVerified = vi.fn()
    renderWithAuth(<MfaPanel onVerified={onVerified} />, fake)
    expect(
      await screen.findByText(/verified with your authenticator app/i),
    ).toBeInTheDocument()
    expect(onVerified).toHaveBeenCalledTimes(1)
  })
  it('walks a new user through setup and verification', async () => {
    const fake = createFakeClient({ session })
    const onVerified = vi.fn()
    renderWithAuth(<MfaPanel onVerified={onVerified} />, fake)
    await userEvent.click(
      await screen.findByRole('button', { name: 'Set up authenticator app' }),
    )
    expect(await screen.findByAltText(/qr code/i)).toBeInTheDocument()
    expect(screen.getByText('SECRETKEY')).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('6-digit code'), '12ab')
    await userEvent.click(screen.getByRole('button', { name: 'Verify' }))
    expect(
      await screen.findByText(/6-digit code/i, {
        selector: 'div[role=alert], p[role=alert]',
      }),
    ).toBeInTheDocument()
    expect(fake.auth.mfa.challengeAndVerify).not.toHaveBeenCalled()
    await userEvent.clear(screen.getByLabelText('6-digit code'))
    await userEvent.type(screen.getByLabelText('6-digit code'), '123 456')
    await userEvent.click(screen.getByRole('button', { name: 'Verify' }))
    await waitFor(() =>
      expect(fake.auth.mfa.challengeAndVerify).toHaveBeenCalledWith({
        factorId: 'factor-1',
        code: '123456',
      }),
    )
    expect(
      await screen.findByText(/verified with your authenticator app/i),
    ).toBeInTheDocument()
    expect(onVerified).toHaveBeenCalledTimes(1)
  })
  it('asks for a code straight away when a verified factor already exists (no new enrolment)', async () => {
    const fake = createFakeClient({ session })
    fake.auth.mfa.listFactors.mockResolvedValue({
      data: { all: [], totp: [{ id: 'old-factor' }] },
      error: null,
    } as never)
    renderWithAuth(<MfaPanel onVerified={vi.fn()} />, fake)
    await userEvent.type(await screen.findByLabelText('6-digit code'), '654321')
    await userEvent.click(screen.getByRole('button', { name: 'Verify' }))
    await waitFor(() =>
      expect(fake.auth.mfa.challengeAndVerify).toHaveBeenCalledWith({
        factorId: 'old-factor',
        code: '654321',
      }),
    )
    expect(fake.auth.mfa.enroll).not.toHaveBeenCalled()
  })
  it('does not report verified when the code is rejected', async () => {
    const fake = createFakeClient({ session })
    fake.auth.mfa.listFactors.mockResolvedValue({
      data: { all: [], totp: [{ id: 'f' }] },
      error: null,
    } as never)
    fake.auth.mfa.challengeAndVerify.mockResolvedValue({
      data: null,
      error: { message: 'bad' },
    } as never)
    const onVerified = vi.fn()
    renderWithAuth(<MfaPanel onVerified={onVerified} />, fake)
    await userEvent.type(await screen.findByLabelText('6-digit code'), '111111')
    await userEvent.click(screen.getByRole('button', { name: 'Verify' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(/not accepted/i)
    expect(onVerified).not.toHaveBeenCalled()
  })
})
