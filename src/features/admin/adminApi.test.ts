import { describe, expect, it } from 'vitest'
import { createFakeClient } from '../../test/fakeSupabase'
import {
  createCode,
  getMyAccess,
  loadAdminData,
  reviewRequest,
  suspendMember,
} from './adminApi'

describe('adminApi (mocked client)', () => {
  it('parses what the caller may do and ignores malformed permission entries', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: { superadmin: true, permissions: ['members.review', 7, null] },
      error: null,
    })
    expect(await getMyAccess(f.client, 't1')).toEqual({
      ok: true,
      access: { superadmin: true, permissions: ['members.review'] },
    })
    expect(f.rpc).toHaveBeenCalledWith('get_my_access', { p_team_id: 't1' })
    f.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: 'XX', message: 'x' },
    } as never)
    expect(await getMyAccess(f.client, 't1')).toMatchObject({ ok: false })
  })
  it('defaults to no access for an unexpected response (never grants more)', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: { permissions: 'everything' },
      error: null,
    })
    expect(await getMyAccess(f.client, 't1')).toEqual({
      ok: true,
      access: { superadmin: false, permissions: [] },
    })
  })
  it('loads lists, attaches names, and orders only by columns clients may read', async () => {
    const f = createFakeClient()
    f.lists.join_requests = [
      { id: 'r1', user_id: 'u1', requested_at: '2026-01-01T00:00:00Z' },
    ]
    f.lists.team_memberships = [
      {
        id: 'm1',
        user_id: 'u1',
        membership_status: 'pending',
        suspended_at: null,
      },
    ]
    f.lists.join_codes = []
    f.lists.profiles = [
      { user_id: 'u1', display_name: 'Ada', organizational_title: null },
    ]
    const r = await loadAdminData(f.client, 't1')
    expect(r.ok && r.data.names.u1.display_name).toBe('Ada')
    expect(f.calls.order).toContain('join_requests.requested_at')
    expect(f.calls.order).toContain('join_codes.created_at')
    // team_memberships.created_at is not a granted column; ordering by it would be refused.
    expect(f.calls.order).not.toContain('team_memberships.created_at')
  })
  it('reports a load failure', async () => {
    const f = createFakeClient()
    f.listError.value = { message: 'x' }
    expect(await loadAdminData(f.client, 't1')).toMatchObject({ ok: false })
  })
  it('sends the documented arguments and maps refusals to an MFA hint', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({ data: { status: 'approved' }, error: null })
    expect(await reviewRequest(f.client, 'r1', 'approve')).toMatchObject({
      ok: true,
      status: 'approved',
    })
    expect(f.rpc).toHaveBeenLastCalledWith('review_join_request', {
      p_request_id: 'r1',
      p_decision: 'approve',
    })
    f.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '42501', message: 'x' },
    } as never)
    expect(await suspendMember(f.client, 'm1')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/authenticator app/i),
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'not_pending' },
      error: null,
    })
    expect(await reviewRequest(f.client, 'r1', 'reject')).toMatchObject({
      ok: false,
      message: expect.stringMatching(/already handled/i),
    })
  })
  it('returns a created code once and rejects a response without one', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: {
        id: 'c1',
        code: 'AAAAA-BBBBB-CCCCC-DDDDD',
        expires_at: '2026-02-01T00:00:00Z',
      },
      error: null,
    })
    expect(await createCode(f.client, 't1', 3, 7, 'label')).toEqual({
      ok: true,
      code: 'AAAAA-BBBBB-CCCCC-DDDDD',
      expiresAt: '2026-02-01T00:00:00Z',
    })
    expect(f.rpc).toHaveBeenLastCalledWith('create_join_code', {
      p_team_id: 't1',
      p_max_uses: 3,
      p_valid_days: 7,
      p_label: 'label',
    })
    f.rpc.mockResolvedValueOnce({ data: { id: 'c2' }, error: null })
    expect(await createCode(f.client, 't1', 1, 1, null)).toMatchObject({
      ok: false,
    })
  })
})
