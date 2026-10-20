import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { ProfileForm } from './ProfileForm'

const signedIn = makeSession('me@example.invalid', 'user-42')

describe('ProfileForm (mocked client)', () => {
  it("creates the user's own profile and sends only permitted fields", async () => {
    const fake = createFakeClient({ session: signedIn, profile: null })
    renderWithAuth(<ProfileForm />, fake)
    await userEvent.type(
      await screen.findByLabelText('Display name'),
      '  Sam  ',
    )
    await userEvent.type(
      screen.getByLabelText(/Organizational title/),
      'UAM Engineer',
    )
    await userEvent.click(screen.getByRole('button', { name: 'Save profile' }))
    await waitFor(() => expect(fake.calls.insert).toHaveLength(1))
    expect(fake.calls.insert[0]).toEqual({
      user_id: 'user-42',
      display_name: 'Sam',
      organizational_title: 'UAM Engineer',
    })
    expect(await screen.findByText('Profile saved.')).toBeInTheDocument()
    expect(new Set(fake.calls.from)).toEqual(new Set(['profiles']))
  })
  it('updates an existing profile without sending user_id', async () => {
    const fake = createFakeClient({
      session: signedIn,
      profile: { display_name: 'Old', organizational_title: null },
    })
    renderWithAuth(<ProfileForm />, fake)
    const name = await screen.findByLabelText('Display name')
    expect(name).toHaveValue('Old')
    await userEvent.clear(name)
    await userEvent.type(name, 'New')
    await userEvent.click(screen.getByRole('button', { name: 'Save profile' }))
    await waitFor(() => expect(fake.calls.update).toHaveLength(1))
    expect(fake.calls.update[0]).toEqual({
      display_name: 'New',
      organizational_title: null,
    })
    expect(fake.calls.insert).toHaveLength(0)
  })
  it('validates locally without calling the database', async () => {
    const fake = createFakeClient({ session: signedIn, profile: null })
    renderWithAuth(<ProfileForm />, fake)
    await screen.findByLabelText('Display name')
    await userEvent.click(screen.getByRole('button', { name: 'Save profile' }))
    expect(await screen.findByText('Enter a display name.')).toBeInTheDocument()
    expect(fake.calls.insert).toHaveLength(0)
  })
  it('shows an error when saving fails', async () => {
    const fake = createFakeClient({ session: signedIn, profile: null })
    fake.profileState.writeError = { message: 'denied' }
    renderWithAuth(<ProfileForm />, fake)
    await userEvent.type(await screen.findByLabelText('Display name'), 'Sam')
    await userEvent.click(screen.getByRole('button', { name: 'Save profile' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /could not save/i,
    )
  })
})
