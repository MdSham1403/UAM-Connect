import { screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { MembershipGate } from '../membership/MembershipGate'

const session = makeSession('me@example.invalid', 'u1')
const approved = { id: 'm1', team_id: 't1', membership_status: 'approved' }

function setup(access: { superadmin: boolean; permissions: string[] }) {
  const fake = createFakeClient({
    session,
    membership: approved,
    teamName: 'Synthetic Team',
  })
  fake.rpc.mockImplementation((async (name: string) => ({
    data:
      name === 'get_my_access'
        ? access
        : name === 'team_directory'
          ? [
              {
                membership_id: 'm1',
                display_name: 'Me',
                organizational_title: null,
                roles: [],
              },
            ]
          : name === 'list_operational_roles'
            ? []
            : { status: 'ok' },
    error: null,
  })) as never)
  return fake
}

describe('approved member screen (mocked client)', () => {
  it('shows the directory to an ordinary member and no role administration', async () => {
    const fake = setup({ superadmin: false, permissions: [] })
    renderWithAuth(<MembershipGate />, fake)
    expect(
      await screen.findByRole('heading', { name: 'Team directory' }),
    ).toBeInTheDocument()
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('get_my_access', {
        p_team_id: 't1',
      }),
    )
    expect(
      screen.queryByRole('heading', { name: 'Operational roles' }),
    ).not.toBeInTheDocument()
    expect(fake.rpc.mock.calls.map((c) => c[0])).not.toContain(
      'list_operational_roles',
    )
  })
  it('shows role administration only to a holder of the role-management permission', async () => {
    const withIt = setup({
      superadmin: false,
      permissions: ['operational_roles.manage'],
    })
    renderWithAuth(<MembershipGate />, withIt)
    expect(
      await screen.findByRole('heading', { name: 'Operational roles' }),
    ).toBeInTheDocument()
  })
  it('does not show role administration to an Admin who lacks that permission', async () => {
    const fake = setup({ superadmin: false, permissions: ['members.review'] })
    renderWithAuth(<MembershipGate />, fake)
    await screen.findByRole('heading', { name: 'Team directory' })
    await waitFor(() =>
      expect(fake.rpc).toHaveBeenCalledWith('get_my_access', {
        p_team_id: 't1',
      }),
    )
    expect(
      screen.queryByRole('heading', { name: 'Operational roles' }),
    ).not.toBeInTheDocument()
  })
})
