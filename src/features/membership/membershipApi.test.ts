import { describe, expect, it } from 'vitest'
import { createFakeClient } from '../../test/fakeSupabase'
import {
  fetchMyMembership,
  fetchTeamName,
  redeemJoinCode,
} from './membershipApi'

const input = {
  code: 'ABCDE-12345-ABCDE-12345',
  displayName: 'Sam',
  title: null,
}

describe('fetchMyMembership / fetchTeamName (mocked client)', () => {
  it('returns null when the user has no membership row', async () => {
    const f = createFakeClient()
    expect(await fetchMyMembership(f.client, 'u1')).toEqual({
      ok: true,
      membership: null,
    })
    expect(f.calls.from).toEqual(['team_memberships'])
  })
  it('returns the status and reports a load failure safely', async () => {
    const f = createFakeClient({
      membership: { id: 'm', team_id: 't', membership_status: 'pending' },
    })
    expect(await fetchMyMembership(f.client, 'u1')).toMatchObject({
      ok: true,
      membership: { membership_status: 'pending' },
    })
    f.membershipState.error = { message: 'x' }
    expect(await fetchMyMembership(f.client, 'u1')).toMatchObject({ ok: false })
  })
  it('returns the team name only when a row comes back', async () => {
    expect(
      await fetchTeamName(
        createFakeClient({ teamName: 'Synthetic Team' }).client,
        't',
      ),
    ).toBe('Synthetic Team')
    expect(await fetchTeamName(createFakeClient().client, 't')).toBeNull()
  })
})

describe('redeemJoinCode (mocked client)', () => {
  it('calls the server function with the documented argument names and nothing else', async () => {
    const f = createFakeClient()
    expect(await redeemJoinCode(f.client, input)).toEqual({
      ok: true,
      status: 'pending',
    })
    expect(f.rpc).toHaveBeenCalledWith('redeem_join_code', {
      p_code: input.code,
      p_display_name: 'Sam',
      p_title: null,
    })
  })
  it('accepts already_pending and already_member as non-errors', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: { status: 'already_pending' },
      error: null,
    })
    expect(await redeemJoinCode(f.client, input)).toEqual({
      ok: true,
      status: 'already_pending',
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'already_member' },
      error: null,
    })
    expect(await redeemJoinCode(f.client, input)).toEqual({
      ok: true,
      status: 'already_member',
    })
  })
  it('gives one generic message for any bad code and distinct messages for limits and blocks', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: { status: 'invalid_code' },
      error: null,
    })
    expect(await redeemJoinCode(f.client, input)).toMatchObject({
      ok: false,
      message: expect.stringMatching(/not valid/i),
    })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'rate_limited' },
      error: null,
    })
    expect(await redeemJoinCode(f.client, input)).toMatchObject({
      message: expect.stringMatching(/too many/i),
    })
    f.rpc.mockResolvedValueOnce({ data: { status: 'blocked' }, error: null })
    expect(await redeemJoinCode(f.client, input)).toMatchObject({
      message: expect.stringMatching(/restricted/i),
    })
  })
  it('maps database errors and treats unknown statuses as failures', async () => {
    const f = createFakeClient()
    f.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '42501', message: 'email address not confirmed' },
    } as never)
    expect(await redeemJoinCode(f.client, input)).toMatchObject({
      message: expect.stringMatching(/confirm your email/i),
    })
    f.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: '22023', message: 'x' },
    } as never)
    expect(await redeemJoinCode(f.client, input)).toMatchObject({ ok: false })
    f.rpc.mockResolvedValueOnce({
      data: { status: 'approved_automatically' },
      error: null,
    })
    expect(await redeemJoinCode(f.client, input)).toMatchObject({ ok: false })
    f.rpc.mockRejectedValueOnce(new Error('offline'))
    expect(await redeemJoinCode(f.client, input)).toMatchObject({
      message: expect.stringMatching(/reach the server/i),
    })
  })
})
