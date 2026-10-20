import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { RoleManager } from './RoleManager'

const session = makeSession('admin@example.invalid', 'admin-1')
const ROLES = [
  {
    id: 'r-q',
    name: 'Queue Manager',
    description: 'owns the queue',
    is_active: true,
    member_count: 1,
  },
  {
    id: 'r-b',
    name: 'BAU / Ticketing',
    description: null,
    is_active: true,
    member_count: 0,
  },
  {
    id: 'r-old',
    name: 'Reconciliation',
    description: null,
    is_active: false,
    member_count: 0,
  },
]
const DIRECTORY = [
  {
    membership_id: 'm-ada',
    display_name: 'Ada',
    organizational_title: null,
    roles: [{ id: 'r-q', name: 'Queue Manager', is_primary: true }],
  },
  {
    membership_id: 'm-bob',
    display_name: 'Bob',
    organizational_title: null,
    roles: [],
  },
]

function setup(change: unknown = { status: 'created' }) {
  const fake = createFakeClient({ session })
  fake.rpc.mockImplementation((async (name: string) => ({
    data:
      name === 'list_operational_roles'
        ? ROLES
        : name === 'team_directory'
          ? DIRECTORY
          : change,
    error: null,
  })) as never)
  return fake
}
const changeCalls = (fake: ReturnType<typeof setup>) =>
  fake.rpc.mock.calls.filter(
    (c) =>
      !['list_operational_roles', 'team_directory'].includes(c[0] as string),
  )

describe('RoleManager (mocked client)', () => {
  it('disables every change until the authenticator is verified, and says why', async () => {
    renderWithAuth(<RoleManager teamId="t1" aal2={false} />, setup())
    await screen
      .findByText('Queue Manager', {
        selector: 'span, li, label, option, input',
      })
      .catch(() => null)
    await screen.findAllByRole('button', { name: /save name/i })
    expect(
      screen.getByText(/verify your authenticator code/i),
    ).toBeInTheDocument()
    for (const b of [
      screen.getByRole('button', { name: 'Add role' }),
      screen.getByRole('button', { name: 'Assign role' }),
      ...screen.getAllByRole('button', { name: /save name/i }),
    ]) {
      expect(b).toBeDisabled()
    }
  })
  it('creates a role (trimmed) and reloads the lists', async () => {
    const fake = setup({ status: 'created' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    const form = screen.getByRole('form', { name: 'Create operational role' })
    await userEvent.type(
      within(form).getByLabelText('New role name'),
      '  Escalations  ',
    )
    await userEvent.type(
      within(form).getByLabelText(/description/i),
      'second line',
    )
    await userEvent.click(
      within(form).getByRole('button', { name: 'Add role' }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(1))
    expect(changeCalls(fake)[0]).toEqual([
      'create_operational_role',
      { p_team_id: 't1', p_name: 'Escalations', p_description: 'second line' },
    ])
    expect(await screen.findByText('Role created.')).toBeInTheDocument()
  })
  it('refuses a blank name without calling the server', async () => {
    const fake = setup()
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    await userEvent.click(screen.getByRole('button', { name: 'Add role' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /1 to 60 characters/i,
    )
    expect(changeCalls(fake)).toHaveLength(0)
  })
  it('shows the duplicate-name message from the server', async () => {
    const fake = setup({ status: 'duplicate' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    await userEvent.type(screen.getByLabelText('New role name'), 'retain')
    await userEvent.click(screen.getByRole('button', { name: 'Add role' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /already exists/i,
    )
  })
  it('renames a role', async () => {
    const fake = setup({ status: 'updated' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    const form = await screen.findByRole('form', { name: 'Edit Queue Manager' })
    const input = within(form).getByLabelText('Role name')
    await userEvent.clear(input)
    await userEvent.type(input, 'Queue Lead')
    await userEvent.click(
      within(form).getByRole('button', { name: 'Save name' }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(1))
    expect(changeCalls(fake)[0]).toEqual([
      'update_operational_role',
      { p_role_id: 'r-q', p_name: 'Queue Lead' },
    ])
  })
  it('deactivates and reactivates; inactive roles are not offered for assignment', async () => {
    const fake = setup({ status: 'updated' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    const assign = screen.getByRole('form', { name: 'Assign operational role' })
    expect(
      within(assign).queryByRole('option', { name: 'Reconciliation' }),
    ).not.toBeInTheDocument()
    expect(
      within(assign).getByRole('option', { name: 'Queue Manager' }),
    ).toBeInTheDocument()
    await userEvent.click(
      screen.getByRole('button', { name: 'Deactivate BAU / Ticketing' }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(1))
    expect(changeCalls(fake)[0]).toEqual([
      'update_operational_role',
      { p_role_id: 'r-b', p_is_active: false },
    ])
    await userEvent.click(
      screen.getByRole('button', { name: 'Reactivate Reconciliation' }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(2))
    expect(changeCalls(fake)[1]).toEqual([
      'update_operational_role',
      { p_role_id: 'r-old', p_is_active: true },
    ])
  })
  it('assigns a role to a member, optionally as primary', async () => {
    const fake = setup({ status: 'assigned' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    const form = screen.getByRole('form', { name: 'Assign operational role' })
    await userEvent.selectOptions(
      within(form).getByLabelText('Member'),
      'm-bob',
    )
    await userEvent.selectOptions(within(form).getByLabelText('Role'), 'r-b')
    await userEvent.click(within(form).getByLabelText(/primary role/i))
    await userEvent.click(
      within(form).getByRole('button', { name: 'Assign role' }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(1))
    expect(changeCalls(fake)[0]).toEqual([
      'assign_operational_role',
      { p_membership_id: 'm-bob', p_role_id: 'r-b', p_is_primary: true },
    ])
  })
  it('requires a member and a role before calling the server', async () => {
    const fake = setup()
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await screen.findAllByRole('button', { name: /save name/i })
    await userEvent.click(screen.getByRole('button', { name: 'Assign role' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /choose a member and a role/i,
    )
    expect(changeCalls(fake)).toHaveLength(0)
  })
  it('removes a role from a member', async () => {
    const fake = setup({ status: 'unassigned' })
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await userEvent.click(
      await screen.findByRole('button', {
        name: 'Remove Queue Manager from Ada',
      }),
    )
    await waitFor(() => expect(changeCalls(fake)).toHaveLength(1))
    expect(changeCalls(fake)[0]).toEqual([
      'unassign_operational_role',
      { p_membership_id: 'm-ada', p_role_id: 'r-q' },
    ])
  })
  it('shows the refusal when the server says no (for example a missing MFA session)', async () => {
    const fake = createFakeClient({ session })
    fake.rpc.mockImplementation((async (name: string) =>
      name === 'list_operational_roles'
        ? { data: ROLES, error: null }
        : name === 'team_directory'
          ? { data: DIRECTORY, error: null }
          : { data: null, error: { code: '42501' } }) as never)
    renderWithAuth(<RoleManager teamId="t1" aal2 />, fake)
    await userEvent.click(
      await screen.findByRole('button', {
        name: 'Remove Queue Manager from Ada',
      }),
    )
    expect(await screen.findByRole('alert')).toHaveTextContent(/not permitted/i)
  })
})
