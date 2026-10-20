import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { createFakeClient, makeSession } from '../../test/fakeSupabase'
import { renderWithAuth } from '../../test/renderWithAuth'
import { TeamDirectory } from './TeamDirectory'

const session = makeSession('me@example.invalid', 'u1')
const DIRECTORY = [
  {
    membership_id: 'm1',
    display_name: 'Ada Lovelace',
    organizational_title: 'UAM Engineer',
    roles: [
      { id: 'r1', name: 'Queue Manager', is_primary: true },
      { id: 'r2', name: 'Retain', is_primary: false },
    ],
  },
  {
    membership_id: 'm2',
    display_name: 'Bob Stone',
    organizational_title: null,
    roles: [],
  },
]

function setup(data: unknown = DIRECTORY) {
  const fake = createFakeClient({ session })
  fake.rpc.mockImplementation((async () => ({ data, error: null })) as never)
  return fake
}

describe('TeamDirectory (mocked client)', () => {
  it('lists names, titles and roles (several roles per member), marking the primary', async () => {
    const fake = setup()
    renderWithAuth(<TeamDirectory teamId="t1" />, fake)
    expect(await screen.findByText('Ada Lovelace')).toBeInTheDocument()
    expect(screen.getByText('UAM Engineer')).toBeInTheDocument()
    expect(screen.getByText(/Queue Manager/)).toBeInTheDocument()
    expect(screen.getByText('(primary)')).toBeInTheDocument()
    expect(screen.getByText(/Retain/)).toBeInTheDocument()
    expect(screen.getByText('No operational roles')).toBeInTheDocument()
    expect(fake.rpc).toHaveBeenCalledWith('team_directory', { p_team_id: 't1' })
  })
  it('filters by name, title or role', async () => {
    renderWithAuth(<TeamDirectory teamId="t1" />, setup())
    await screen.findByText('Ada Lovelace')
    const box = screen.getByLabelText(/search by name, title or role/i)
    await userEvent.type(box, 'retain')
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument()
    expect(screen.queryByText('Bob Stone')).not.toBeInTheDocument()
    await userEvent.clear(box)
    await userEvent.type(box, 'stone')
    expect(screen.queryByText('Ada Lovelace')).not.toBeInTheDocument()
    await userEvent.clear(box)
    await userEvent.type(box, 'zzz')
    expect(screen.getByText(/no one matches/i)).toBeInTheDocument()
  })
  it('shows an empty state', async () => {
    renderWithAuth(<TeamDirectory teamId="t1" />, setup([]))
    expect(
      await screen.findByText(/no members to show yet/i),
    ).toBeInTheDocument()
  })
  it('shows an error with a retry when the server refuses or fails', async () => {
    const fake = createFakeClient({ session })
    fake.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } })
    renderWithAuth(<TeamDirectory teamId="t1" />, fake)
    expect(await screen.findByRole('alert')).toHaveTextContent(
      /could not load/i,
    )
    fake.rpc.mockImplementation((async () => ({
      data: DIRECTORY,
      error: null,
    })) as never)
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Ada Lovelace')).toBeInTheDocument()
  })
})
