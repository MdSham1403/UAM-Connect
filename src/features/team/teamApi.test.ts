import { describe, expect, it } from 'vitest'
import { createFakeClient } from '../../test/fakeSupabase'
import {
  assignRole,
  createRole,
  getDirectory,
  listRoles,
  parseDirectory,
  parseRoles,
  unassignRole,
  updateRole,
} from './teamApi'

describe('parsing (never trusts the response shape)', () => {
  it('reads a directory, defaults missing names and skips malformed entries', () => {
    const out = parseDirectory([
      {
        membership_id: 'm1',
        display_name: 'Ada',
        organizational_title: 'UAM Engineer',
        roles: [{ id: 'r1', name: 'Retain', is_primary: true }, { nope: 1 }],
      },
      { membership_id: 'm2', display_name: '', roles: 'oops' },
      { display_name: 'no id' },
      42,
    ])
    expect(out).toEqual([
      {
        membership_id: 'm1',
        display_name: 'Ada',
        organizational_title: 'UAM Engineer',
        roles: [{ id: 'r1', name: 'Retain', is_primary: true }],
      },
      {
        membership_id: 'm2',
        display_name: 'Unnamed member',
        organizational_title: null,
        roles: [],
      },
    ])
  })
  it('returns null for anything that is not a list', () => {
    expect(parseDirectory({ status: 'x' })).toBeNull()
    expect(parseRoles(null)).toBeNull()
  })
  it('reads roles and treats a missing active flag as active', () => {
    expect(
      parseRoles([
        { id: 'r', name: 'N', description: null, member_count: 2 },
        { id: 'r2' },
      ]),
    ).toEqual([
      {
        id: 'r',
        name: 'N',
        description: null,
        is_active: true,
        member_count: 2,
      },
    ])
  })
})

describe('reads (mocked client)', () => {
  it('call the server functions with the team id', async () => {
    const f = createFakeClient()
    expect(await getDirectory(f.client, 't1')).toEqual({ ok: true, value: [] })
    expect(await listRoles(f.client, 't1')).toEqual({ ok: true, value: [] })
    expect(f.rpc).toHaveBeenCalledWith('team_directory', { p_team_id: 't1' })
    expect(f.rpc).toHaveBeenCalledWith('list_operational_roles', {
      p_team_id: 't1',
    })
  })
  it('report errors, bad shapes and thrown failures safely', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } })
    expect(await getDirectory(f.client, 't1')).toMatchObject({ ok: false })
    f.rpc.mockResolvedValueOnce({ data: { status: 'pending' }, error: null })
    expect(await listRoles(f.client, 't1')).toMatchObject({ ok: false })
    f.rpc.mockRejectedValueOnce(new Error('offline'))
    expect(await getDirectory(f.client, 't1')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/reach the server/i),
    })
  })
})

describe('changes (mocked client)', () => {
  it('create sends the documented argument names', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: { status: 'created', id: 'x' },
      error: null,
    })
    expect(await createRole(f.client, 't1', 'Escalations', null)).toEqual({
      ok: true,
      status: 'created',
    })
    expect(f.rpc).toHaveBeenCalledWith('create_operational_role', {
      p_team_id: 't1',
      p_name: 'Escalations',
      p_description: null,
    })
  })
  it('a duplicate name is a message, not a crash', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({ data: { status: 'duplicate' }, error: null })
    expect(await createRole(f.client, 't1', 'Retain', null)).toMatchObject({
      ok: false,
      message: expect.stringMatching(/already exists/i),
    })
  })
  it('update sends only the fields that were provided', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValue({ data: { status: 'updated' }, error: null })
    await updateRole(f.client, 'r1', { name: 'New' })
    expect(f.rpc).toHaveBeenLastCalledWith('update_operational_role', {
      p_role_id: 'r1',
      p_name: 'New',
    })
    await updateRole(f.client, 'r1', { isActive: false })
    expect(f.rpc).toHaveBeenLastCalledWith('update_operational_role', {
      p_role_id: 'r1',
      p_is_active: false,
    })
  })
  it('assign and unassign send membership and role ids; no-op unassign is fine', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({ data: { status: 'assigned' }, error: null })
    expect(await assignRole(f.client, 'm1', 'r1', true)).toEqual({
      ok: true,
      status: 'assigned',
    })
    expect(f.rpc).toHaveBeenLastCalledWith('assign_operational_role', {
      p_membership_id: 'm1',
      p_role_id: 'r1',
      p_is_primary: true,
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'not_assigned' },
      error: null,
    })
    expect(await unassignRole(f.client, 'm1', 'r1')).toMatchObject({ ok: true })
    expect(f.rpc).toHaveBeenLastCalledWith('unassign_operational_role', {
      p_membership_id: 'm1',
      p_role_id: 'r1',
    })
  })
  it('maps server refusals and statuses to plain messages', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } })
    expect(await assignRole(f.client, 'm', 'r', false)).toMatchObject({
      message: expect.stringMatching(/not permitted/i),
    })
    f.rpc.mockResolvedValueOnce({ data: null, error: { code: '22023' } })
    expect(await assignRole(f.client, 'm', 'r', false)).toMatchObject({
      message: expect.stringMatching(/check the values/i),
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'role_inactive' },
      error: null,
    })
    expect(await assignRole(f.client, 'm', 'r', false)).toMatchObject({
      message: expect.stringMatching(/inactive/i),
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'not_approved' },
      error: null,
    })
    expect(await assignRole(f.client, 'm', 'r', false)).toMatchObject({
      message: expect.stringMatching(/approved members/i),
    })
    f.rpc.mockResolvedValueOnce({ data: { status: 'surprise' }, error: null })
    expect(await assignRole(f.client, 'm', 'r', false)).toMatchObject({
      ok: false,
    })
  })
})
