import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import {
  authError,
  createFakeClient,
  makeSession,
} from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { RequireAuth } from './RequireAuth'

const PW = 'Str0ngPassword1'

async function openUnauthenticated(fake = createFakeClient()) {
  renderWithAuth(
    <RequireAuth>
      <p>PROTECTED CONTENT</p>
    </RequireAuth>,
    fake,
  )
  await screen.findByRole('heading', { name: 'Sign in' })
  return fake
}

describe('sign-in screen (mocked client)', () => {
  it('never renders protected content while unauthenticated', async () => {
    await openUnauthenticated()
    expect(screen.queryByText('PROTECTED CONTENT')).not.toBeInTheDocument()
  })
  it('shows a loading state before the session check finishes', () => {
    renderWithAuth(
      <RequireAuth>
        <p>PROTECTED CONTENT</p>
      </RequireAuth>,
      createFakeClient(),
    )
    expect(screen.getByRole('status')).toHaveTextContent(/loading/i)
    expect(screen.queryByText('PROTECTED CONTENT')).not.toBeInTheDocument()
  })
  it('validates input without calling the server', async () => {
    const fake = await openUnauthenticated()
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(
      await screen.findByText('Enter your email address.'),
    ).toBeInTheDocument()
    expect(screen.getByText('Enter your password.')).toBeInTheDocument()
    expect(fake.auth.signInWithPassword).not.toHaveBeenCalled()
  })
  it('signs in and then renders protected content', async () => {
    const fake = await openUnauthenticated()
    await userEvent.type(screen.getByLabelText('Email'), 'a@example.invalid')
    await userEvent.type(screen.getByLabelText('Password'), 'whatever')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    await waitFor(() =>
      expect(fake.auth.signInWithPassword).toHaveBeenCalledWith({
        email: 'a@example.invalid',
        password: 'whatever',
      }),
    )
    act(() => fake.emit('SIGNED_IN', makeSession()))
    expect(await screen.findByText('PROTECTED CONTENT')).toBeInTheDocument()
  })
  it('shows one generic error for a wrong password', async () => {
    const fake = await openUnauthenticated()
    fake.auth.signInWithPassword.mockResolvedValueOnce({
      data: {},
      error: authError('invalid_credentials'),
    } as never)
    await userEvent.type(screen.getByLabelText('Email'), 'a@example.invalid')
    await userEvent.type(screen.getByLabelText('Password'), 'nope')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Invalid email or password.',
    )
  })
  it('lets password managers fill the right fields', async () => {
    await openUnauthenticated()
    expect(screen.getByLabelText('Email')).toHaveAttribute(
      'autocomplete',
      'email',
    )
    expect(screen.getByLabelText('Password')).toHaveAttribute(
      'autocomplete',
      'current-password',
    )
    expect(screen.getByLabelText('Password')).toHaveAttribute(
      'type',
      'password',
    )
  })
})

describe('sign-up screen (mocked client)', () => {
  async function openSignUp() {
    const fake = await openUnauthenticated()
    await userEvent.click(
      screen.getByRole('button', { name: 'Create account' }),
    )
    await screen.findByRole('heading', { name: 'Create account' })
    return fake
  }
  it('rejects a weak password and a mismatch locally', async () => {
    const fake = await openSignUp()
    await userEvent.type(screen.getByLabelText('Email'), 'a@example.invalid')
    await userEvent.type(screen.getByLabelText('Password'), 'short')
    await userEvent.type(screen.getByLabelText('Confirm password'), 'different')
    await userEvent.click(
      screen.getByRole('button', { name: 'Create account' }),
    )
    expect(
      await screen.findByText('Use at least 12 characters.'),
    ).toBeInTheDocument()
    expect(screen.getByText('Passwords do not match.')).toBeInTheDocument()
    expect(fake.auth.signUp).not.toHaveBeenCalled()
  })
  it('asks the user to confirm their email and is clear that it grants no team access', async () => {
    const fake = await openSignUp()
    await userEvent.type(screen.getByLabelText('Email'), 'a@example.invalid')
    await userEvent.type(screen.getByLabelText('Password'), PW)
    await userEvent.type(screen.getByLabelText('Confirm password'), PW)
    await userEvent.click(
      screen.getByRole('button', { name: 'Create account' }),
    )
    expect(await screen.findByRole('status')).toHaveTextContent(
      /confirmation link/i,
    )
    expect(fake.auth.signUp).toHaveBeenCalledWith(
      expect.objectContaining({ email: 'a@example.invalid', password: PW }),
    )
    expect(
      screen.getByText(/does not give access to team information/i),
    ).toBeInTheDocument()
    expect(screen.queryByText('PROTECTED CONTENT')).not.toBeInTheDocument()
  })
  it('does not sign the user in if the server returns a session at sign-up', async () => {
    const fake = await openSignUp()
    fake.auth.signUp.mockResolvedValueOnce({
      data: { user: { id: 'x' }, session: makeSession() },
      error: null,
    } as never)
    await userEvent.type(screen.getByLabelText('Email'), 'a@example.invalid')
    await userEvent.type(screen.getByLabelText('Password'), PW)
    await userEvent.type(screen.getByLabelText('Confirm password'), PW)
    await userEvent.click(
      screen.getByRole('button', { name: 'Create account' }),
    )
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /confirmation is not enabled/i,
    )
    expect(screen.queryByText('PROTECTED CONTENT')).not.toBeInTheDocument()
  })
})

describe('forgot and reset password (mocked client)', () => {
  it('shows the same message whether or not the account exists', async () => {
    const fake = await openUnauthenticated()
    await userEvent.click(
      screen.getByRole('button', { name: 'Forgot password?' }),
    )
    await userEvent.type(
      await screen.findByLabelText('Email'),
      'nobody@example.invalid',
    )
    await userEvent.click(
      screen.getByRole('button', { name: 'Reset password' }),
    )
    expect(await screen.findByRole('status')).toHaveTextContent(
      /if an account exists/i,
    )
    expect(fake.auth.resetPasswordForEmail).toHaveBeenCalledWith(
      'nobody@example.invalid',
      {
        redirectTo: expect.stringContaining('flow=recovery'),
      },
    )
  })
  it('replaces everything with the reset form during recovery, validates, then continues', async () => {
    const fake = createFakeClient()
    renderWithAuth(
      <RequireAuth>
        <p>PROTECTED CONTENT</p>
      </RequireAuth>,
      fake,
    )
    await screen.findByRole('heading', { name: 'Sign in' })
    act(() => fake.emit('PASSWORD_RECOVERY', makeSession()))
    expect(
      await screen.findByRole('heading', { name: 'Choose a new password' }),
    ).toBeInTheDocument()
    expect(screen.queryByText('PROTECTED CONTENT')).not.toBeInTheDocument()

    await userEvent.type(screen.getByLabelText('New password'), PW)
    await userEvent.type(
      screen.getByLabelText('Confirm new password'),
      'Mismatch12345',
    )
    await userEvent.click(
      screen.getByRole('button', { name: 'Save new password' }),
    )
    expect(
      await screen.findByText('Passwords do not match.'),
    ).toBeInTheDocument()
    expect(fake.auth.updateUser).not.toHaveBeenCalled()

    await userEvent.clear(screen.getByLabelText('Confirm new password'))
    await userEvent.type(screen.getByLabelText('Confirm new password'), PW)
    await userEvent.click(
      screen.getByRole('button', { name: 'Save new password' }),
    )
    await waitFor(() =>
      expect(fake.auth.updateUser).toHaveBeenCalledWith({ password: PW }),
    )
    expect(await screen.findByText('PROTECTED CONTENT')).toBeInTheDocument()
  })
  it('lets the user abandon recovery, which signs them out', async () => {
    const fake = createFakeClient()
    renderWithAuth(
      <RequireAuth>
        <p>PROTECTED CONTENT</p>
      </RequireAuth>,
      fake,
    )
    await screen.findByRole('heading', { name: 'Sign in' })
    act(() => fake.emit('PASSWORD_RECOVERY', makeSession()))
    await userEvent.click(
      await screen.findByRole('button', { name: 'Cancel and sign out' }),
    )
    expect(
      await screen.findByRole('heading', { name: 'Sign in' }),
    ).toBeInTheDocument()
    expect(fake.auth.signOut).toHaveBeenCalled()
  })
})
