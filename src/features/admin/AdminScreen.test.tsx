import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { AdminScreen } from './AdminScreen'

const admin = {
  superadmin: false,
  permissions: [
    'members.review',
    'members.suspend',
    'join_codes.manage',
    'app_roles.grant_basic',
  ],
}
const session = makeSession('admin@example.invalid', 'me-1')

function setup(opts: { aal2?: boolean } = {}) {
  const fake = createFakeClient({ session })
  if (opts.aal2) {
    fake.auth.mfa.getAuthenticatorAssuranceLevel.mockResolvedValue({
      data: { currentLevel: 'aal2', nextLevel: 'aal2' },
      error: null,
    } as never)
  }
  fake.lists.join_requests = [
    { id: 'r1', user_id: 'u-ada', requested_at: '2026-01-01T09:00:00Z' },
  ]
  fake.lists.team_memberships = [
    {
      id: 'm-me',
      user_id: 'me-1',
      membership_status: 'approved',
      suspended_at: null,
    },
    {
      id: 'm-bob',
      user_id: 'u-bob',
      membership_status: 'approved',
      suspended_at: null,
    },
    {
      id: 'm-cy',
      user_id: 'u-cy',
      membership_status: 'suspended',
      suspended_at: '2026-01-02T00:00:00Z',
    },
  ]
  fake.lists.join_codes = [
    {
      id: 'c-live',
      label: 'Spring',
      expires_at: '2999-01-01T00:00:00Z',
      max_uses: 3,
      use_count: 1,
      revoked_at: null,
    },
    {
      id: 'c-dead',
      label: 'Old',
      expires_at: '2999-01-01T00:00:00Z',
      max_uses: 3,
      use_count: 0,
      revoked_at: '2026-01-01T00:00:00Z',
    },
  ]
  fake.lists.profiles = [
    {
      user_id: 'u-ada',
      display_name: 'Ada',
      organizational_title: 'UAM Engineer',
    },
    { user_id: 'u-bob', display_name: 'Bob', organizational_title: null },
    { user_id: 'u-cy', display_name: 'Cy', organizational_title: null },
    { user_id: 'me-1', display_name: 'Me Admin', organizational_title: null },
  ]
  return fake
}

describe('AdminScreen (mocked client)', () => {
  it('lists requests, members and codes with names, and offers MFA verification first', async () => {
    const fake = setup()
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    expect(await screen.findByText(/Ada, UAM Engineer/)).toBeInTheDocument()
    expect(screen.getByText(/Bob/)).toBeInTheDocument()
    expect(screen.getByText(/Spring: 1\/3 used/)).toBeInTheDocument()
    expect(
      await screen.findByRole('button', { name: 'Set up authenticator app' }),
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Approve' })).toBeDisabled()
    expect(fake.rpc).not.toHaveBeenCalled()
  })
  it('approves and rejects through the server function once verified', async () => {
    const fake = setup({ aal2: true })
    fake.rpc.mockResolvedValue({ data: { status: 'approved' }, error: null })
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    const approve = await screen.findByRole('button', { name: 'Approve' })
    await waitFor(() => expect(approve).toBeEnabled())
    await userEvent.click(approve)
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('review_join_request', {
        p_request_id: 'r1',
        p_decision: 'approve',
      }),
    )
    expect(await screen.findByText('Request approved.')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Reject' }))
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('review_join_request', {
        p_request_id: 'r1',
        p_decision: 'reject',
      }),
    )
  })
  it('creates a code, shows it once with a warning, and validates locally first', async () => {
    const fake = setup({ aal2: true })
    fake.rpc.mockResolvedValue({
      data: {
        id: 'c9',
        code: 'ABCDE-12345-ABCDE-12345',
        expires_at: '2999-01-01T00:00:00Z',
      },
      error: null,
    })
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    const button = await screen.findByRole('button', { name: 'Create code' })
    await waitFor(() => expect(button).toBeEnabled())
    await userEvent.clear(screen.getByLabelText('Number of uses'))
    await userEvent.type(screen.getByLabelText('Number of uses'), '99')
    await userEvent.click(button)
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /between 1 and 50/i,
    )
    expect(fake.rpc).not.toHaveBeenCalled()
    await userEvent.clear(screen.getByLabelText('Number of uses'))
    await userEvent.type(screen.getByLabelText('Number of uses'), '2')
    await userEvent.type(screen.getByLabelText('Label (optional)'), 'Autumn')
    await userEvent.click(button)
    expect(
      await screen.findByText('ABCDE-12345-ABCDE-12345'),
    ).toBeInTheDocument()
    expect(screen.getByText(/will not be shown again/i)).toBeInTheDocument()
    expect(fake.rpc).toHaveBeenCalledWith('create_join_code', {
      p_team_id: 't1',
      p_max_uses: 2,
      p_valid_days: 7,
      p_label: 'Autumn',
    })
  })
  it('revokes only active codes', async () => {
    const fake = setup({ aal2: true })
    fake.rpc.mockResolvedValue({ data: { status: 'revoked' }, error: null })
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    const revokes = await screen.findAllByRole('button', { name: 'Revoke' })
    expect(revokes).toHaveLength(1)
    await waitFor(() => expect(revokes[0]).toBeEnabled())
    await userEvent.click(revokes[0])
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('revoke_join_code', {
        p_code_id: 'c-live',
      }),
    )
  })
  it('offers suspend and reinstate for others, never for yourself', async () => {
    const fake = setup({ aal2: true })
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    await screen.findByText(/Bob/)
    expect(screen.getAllByRole('button', { name: 'Suspend' })).toHaveLength(1) // Bob only, not "Me Admin"
    expect(screen.getAllByRole('button', { name: 'Reinstate' })).toHaveLength(1) // Cy
  })
  it('shows the refusal message when the server says no', async () => {
    const fake = setup({ aal2: true })
    fake.rpc.mockResolvedValue({
      data: null,
      error: { code: '42501', message: 'x' },
    })
    renderWithAuth(<AdminScreen teamId="t1" access={admin} />, fake)
    const approve = await screen.findByRole('button', { name: 'Approve' })
    await waitFor(() => expect(approve).toBeEnabled())
    await userEvent.click(approve)
    expect(await screen.findByRole('alert')).toHaveTextContent(/not permitted/i)
  })
  it('hides sections the viewer has no permission for, and labels a Superadmin', async () => {
    const fake = setup({ aal2: true })
    renderWithAuth(
      <AdminScreen
        teamId="t1"
        access={{ superadmin: false, permissions: ['members.review'] }}
      />,
      fake,
    )
    await screen.findByText(/Ada/)
    expect(screen.queryByText('Joining codes')).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Suspend' }),
    ).not.toBeInTheDocument()
  })
  it('labels the Superadmin', async () => {
    renderWithAuth(
      <AdminScreen
        teamId="t1"
        access={{ superadmin: true, permissions: admin.permissions }}
      />,
      setup({ aal2: true }),
    )
    expect(
      await screen.findByText(/Administration \(Superadmin\)/),
    ).toBeInTheDocument()
  })
})
