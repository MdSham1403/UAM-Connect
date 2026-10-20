import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { useAuth } from './AuthProvider'

function Probe() {
  const { status, notice, user, signOut } = useAuth()
  return (
    <div>
      <p data-testid="status">{status}</p>
      <p data-testid="notice">{notice ?? ''}</p>
      <p data-testid="email">{user?.email ?? ''}</p>
      <button onClick={() => void signOut()}>out</button>
    </div>
  )
}
const status = () => screen.getByTestId('status').textContent
const notice = () => screen.getByTestId('notice').textContent

afterEach(() => window.history.replaceState({}, '', '/'))

describe('AuthProvider (mocked client)', () => {
  it('starts loading, then unauthenticated without a stored session', async () => {
    renderWithAuth(<Probe />, createFakeClient())
    expect(status()).toBe('loading')
    await waitFor(() => expect(status()).toBe('unauthenticated'))
  })
  it('restores an existing session as authenticated', async () => {
    renderWithAuth(
      <Probe />,
      createFakeClient({ session: makeSession('me@example.invalid') }),
    )
    await waitFor(() => expect(status()).toBe('authenticated'))
    expect(screen.getByTestId('email')).toHaveTextContent('me@example.invalid')
  })
  it('shows a notice when the session ends unexpectedly (e.g. refresh failure)', async () => {
    const fake = createFakeClient({ session: makeSession() })
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('authenticated'))
    act(() => fake.emit('SIGNED_OUT', null))
    expect(status()).toBe('unauthenticated')
    expect(notice()).toMatch(/session has ended/i)
  })
  it('does not show that notice for a sign-out the user asked for', async () => {
    const fake = createFakeClient({ session: makeSession() })
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('authenticated'))
    await userEvent.click(screen.getByText('out'))
    await waitFor(() => expect(status()).toBe('unauthenticated'))
    expect(notice()).toBe('')
  })
  it('falls back to unauthenticated with a notice when the session cannot be restored', async () => {
    const fake = createFakeClient()
    fake.auth.getSession.mockResolvedValueOnce({
      data: { session: null },
      error: new Error('x'),
    } as never)
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('unauthenticated'))
    expect(notice()).toMatch(/could not restore/i)
  })
  it('enters recovery when Supabase signals PASSWORD_RECOVERY', async () => {
    const fake = createFakeClient()
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('unauthenticated'))
    act(() => fake.emit('PASSWORD_RECOVERY', makeSession()))
    expect(status()).toBe('recovery')
  })
  it('treats ?flow=recovery with a session as recovery, and cleans the URL', async () => {
    window.history.replaceState({}, '', '/?flow=recovery&code=one-time')
    renderWithAuth(<Probe />, createFakeClient({ session: makeSession() }))
    await waitFor(() => expect(status()).toBe('recovery'))
    expect(window.location.search).toBe('')
  })
  it('verifies a cross-device token link and cleans the URL', async () => {
    window.history.replaceState(
      {},
      '',
      '/?flow=confirm&token_hash=th&type=email',
    )
    const fake = createFakeClient({ session: makeSession() })
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('authenticated'))
    expect(fake.auth.verifyOtp).toHaveBeenCalledWith({
      token_hash: 'th',
      type: 'email',
    })
    expect(window.location.search).toBe('')
  })
  it('does not enter recovery when the recovery link was rejected', async () => {
    window.history.replaceState(
      {},
      '',
      '/?flow=recovery&token_hash=bad&type=recovery',
    )
    const fake = createFakeClient()
    fake.auth.verifyOtp.mockResolvedValueOnce({
      data: {},
      error: new Error('expired'),
    } as never)
    renderWithAuth(<Probe />, fake)
    await waitFor(() => expect(status()).toBe('unauthenticated'))
    expect(notice()).toMatch(/invalid or has expired/i)
  })
  it('shows a fixed message for a link error and never the raw server text', async () => {
    window.history.replaceState(
      {},
      '',
      '/?error=access_denied&error_code=otp_expired&error_description=Raw+server+text',
    )
    renderWithAuth(<Probe />, createFakeClient())
    await waitFor(() => expect(status()).toBe('unauthenticated'))
    expect(notice()).toMatch(/invalid or has expired/i)
    expect(notice()).not.toMatch(/raw server text/i)
  })
})
