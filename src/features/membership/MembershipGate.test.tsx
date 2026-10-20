import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { MembershipGate } from './MembershipGate'

const session = makeSession('me@example.invalid', 'user-9')
const member = (membership_status: string) => ({
  id: 'm1',
  team_id: 't1',
  membership_status,
})
const CODE = 'ABCDE-12345-ABCDE-12345'

async function fillAndSubmit(overrides: { code?: string; name?: string } = {}) {
  await userEvent.type(
    await screen.findByLabelText('Joining code'),
    overrides.code ?? CODE,
  )
  const name = screen.getByLabelText('Your name')
  await userEvent.clear(name)
  await userEvent.type(name, overrides.name ?? 'Sam')
  await userEvent.click(screen.getByRole('button', { name: 'Request to join' }))
}

describe('MembershipGate (mocked client)', () => {
  it('shows the join form to a signed-in user with no membership, and says sign-in is not access', async () => {
    const fake = createFakeClient({ session, membership: null })
    renderWithAuth(<MembershipGate />, fake)
    expect(
      await screen.findByRole('heading', { name: 'Join your team' }),
    ).toBeInTheDocument()
    expect(
      screen.getByText(/does not give access to team information/i),
    ).toBeInTheDocument()
    expect(fake.calls.from).not.toContain('teams')
  })
  it('validates the form without calling the server', async () => {
    const fake = createFakeClient({ session, membership: null })
    renderWithAuth(<MembershipGate />, fake)
    await userEvent.click(
      await screen.findByRole('button', { name: 'Request to join' }),
    )
    expect(
      await screen.findByText('Enter the full joining code.'),
    ).toBeInTheDocument()
    expect(screen.getByText('Enter your name.')).toBeInTheDocument()
    expect(fake.rpc).not.toHaveBeenCalled()
  })
  it('submits the code to the server function and then shows the waiting screen', async () => {
    const fake = createFakeClient({ session, membership: null })
    renderWithAuth(<MembershipGate />, fake)
    // After the redemption the server now has a pending row.
    fake.rpc.mockImplementationOnce(async () => {
      fake.membershipState.row = member('pending')
      return { data: { status: 'pending' }, error: null }
    })
    await fillAndSubmit()
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith(
        'redeem_join_code',
        expect.objectContaining({
          p_code: CODE,
          p_display_name: 'Sam',
          p_title: null,
        }),
      ),
    )
    expect(
      await screen.findByRole('heading', { name: 'Waiting for approval' }),
    ).toBeInTheDocument()
    expect(screen.queryByText(/welcome to/i)).not.toBeInTheDocument()
  })
  it('does not treat the server saying "pending" as approval: approval needs the membership row', async () => {
    const fake = createFakeClient({ session, membership: null })
    renderWithAuth(<MembershipGate />, fake)
    await fillAndSubmit()
    // rpc returned pending but the (fake) database row is still absent: nothing is unlocked.
    await waitFor(() => expect(fake.rpc).toHaveBeenCalled())
    expect(screen.queryByText(/welcome to/i)).not.toBeInTheDocument()
  })
  it('shows a generic error for a bad code and keeps the form', async () => {
    const fake = createFakeClient({ session, membership: null })
    fake.rpc.mockResolvedValueOnce({
      data: { status: 'invalid_code' },
      error: null,
    })
    renderWithAuth(<MembershipGate />, fake)
    await fillAndSubmit()
    expect(await screen.findByRole('alert')).toHaveTextContent(/not valid/i)
    expect(screen.getByLabelText('Joining code')).toBeInTheDocument()
  })
  it('shows the waiting screen for a pending member and lets them re-check', async () => {
    const fake = createFakeClient({ session, membership: member('pending') })
    renderWithAuth(<MembershipGate />, fake)
    expect(
      await screen.findByRole('heading', { name: 'Waiting for approval' }),
    ).toBeInTheDocument()
    fake.membershipState.row = member('approved')
    fake.teamState.name = 'Synthetic Team'
    await userEvent.click(screen.getByRole('button', { name: 'Check status' }))
    expect(
      await screen.findByRole('heading', { name: 'Welcome to Synthetic Team' }),
    ).toBeInTheDocument()
  })
  it('asks the teams table only after approval', async () => {
    const pending = createFakeClient({ session, membership: member('pending') })
    renderWithAuth(<MembershipGate />, pending)
    await screen.findByRole('heading', { name: 'Waiting for approval' })
    expect(pending.calls.from).not.toContain('teams')
  })
  it('lets a rejected user apply again, with an explanation', async () => {
    renderWithAuth(
      <MembershipGate />,
      createFakeClient({ session, membership: member('rejected') }),
    )
    expect(await screen.findByText(/not approved/i)).toBeInTheDocument()
    expect(screen.getByLabelText('Joining code')).toBeInTheDocument()
  })
  it.each(['suspended', 'removed'])(
    'shows a restricted screen with no join form for a %s member',
    async (status) => {
      renderWithAuth(
        <MembershipGate />,
        createFakeClient({ session, membership: member(status) }),
      )
      expect(
        await screen.findByRole('heading', { name: 'Access restricted' }),
      ).toBeInTheDocument()
      expect(screen.queryByLabelText('Joining code')).not.toBeInTheDocument()
    },
  )
  it('shows a retry when the membership cannot be loaded', async () => {
    const fake = createFakeClient({ session })
    fake.membershipState.error = { message: 'boom' }
    renderWithAuth(<MembershipGate />, fake)
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /could not load/i,
    )
    fake.membershipState.error = null
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(
      await screen.findByRole('heading', { name: 'Join your team' }),
    ).toBeInTheDocument()
  })
  it('shows no administration to a plain member and requests no admin data', async () => {
    const fake = createFakeClient({
      session,
      membership: member('approved'),
      teamName: 'Synthetic Team',
    })
    fake.rpc.mockResolvedValue({
      data: { superadmin: false, permissions: [] },
      error: null,
    })
    renderWithAuth(<MembershipGate />, fake)
    expect(
      await screen.findByRole('heading', { name: 'Welcome to Synthetic Team' }),
    ).toBeInTheDocument()
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('get_my_access', {
        p_team_id: 't1',
      }),
    )
    expect(
      screen.queryByRole('heading', { name: /Administration/ }),
    ).not.toBeInTheDocument()
    expect(fake.calls.from).not.toContain('join_requests')
    expect(fake.calls.from).not.toContain('join_codes')
  })
  it('shows administration when the server reports admin permissions', async () => {
    const fake = createFakeClient({
      session,
      membership: member('approved'),
      teamName: 'Synthetic Team',
    })
    fake.rpc.mockResolvedValue({
      data: { superadmin: false, permissions: ['members.review'] },
      error: null,
    })
    renderWithAuth(<MembershipGate />, fake)
    expect(
      await screen.findByRole('heading', { name: 'Administration' }),
    ).toBeInTheDocument()
  })
  it('shows no administration to a pending member (never asks the server)', async () => {
    const fake = createFakeClient({ session, membership: member('pending') })
    renderWithAuth(<MembershipGate />, fake)
    await screen.findByRole('heading', { name: 'Waiting for approval' })
    expect(fake.rpc).not.toHaveBeenCalled()
  })
})
