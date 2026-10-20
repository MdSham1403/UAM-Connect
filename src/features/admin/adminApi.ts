import type { SupabaseClient } from '@supabase/supabase-js'

export interface Access {
  superadmin: boolean
  permissions: string[]
}
export type AccessLoad =
  { ok: true; access: Access } | { ok: false; message: string }
export type ActionResult =
  { ok: true; status: string } | { ok: false; message: string }

export interface PendingRequest {
  id: string
  user_id: string
  requested_at: string
}
export interface MemberRow {
  id: string
  user_id: string
  membership_status: string
  suspended_at: string | null
}
export interface CodeRow {
  id: string
  label: string | null
  expires_at: string
  max_uses: number
  use_count: number
  revoked_at: string | null
}
export interface AdminData {
  pending: PendingRequest[]
  members: MemberRow[]
  codes: CodeRow[]
  names: Record<
    string,
    { display_name: string; organizational_title: string | null }
  >
}
export type AdminLoad =
  { ok: true; data: AdminData } | { ok: false; message: string }

const DENIED =
  'Not permitted. If you are an administrator, verify with your authenticator app first, then try again.'
const FAILED = 'Could not complete that. Check your connection and try again.'

/** What the caller may do. This only decides which screens to show; the database decides access. */
export async function getMyAccess(
  client: SupabaseClient,
  teamId: string,
): Promise<AccessLoad> {
  try {
    const { data, error } = await client.rpc('get_my_access', {
      p_team_id: teamId,
    })
    if (error) return { ok: false, message: FAILED }
    const d = data as { superadmin?: boolean; permissions?: unknown } | null
    const permissions = Array.isArray(d?.permissions)
      ? (d.permissions as unknown[]).filter(
          (p): p is string => typeof p === 'string',
        )
      : []
    return {
      ok: true,
      access: { superadmin: d?.superadmin === true, permissions },
    }
  } catch {
    return { ok: false, message: FAILED }
  }
}

export async function loadAdminData(
  client: SupabaseClient,
  teamId: string,
): Promise<AdminLoad> {
  try {
    const [pending, members, codes] = await Promise.all([
      client
        .from('join_requests')
        .select('id, user_id, requested_at')
        .eq('team_id', teamId)
        .eq('status', 'pending')
        .order('requested_at', { ascending: true }),
      client
        .from('team_memberships')
        .select('id, user_id, membership_status, suspended_at')
        .eq('team_id', teamId),
      client
        .from('join_codes')
        .select('id, label, expires_at, max_uses, use_count, revoked_at')
        .eq('team_id', teamId)
        .order('created_at', { ascending: false }),
    ])
    if (pending.error || members.error || codes.error)
      return { ok: false, message: FAILED }
    const pendingRows = (pending.data ?? []) as PendingRequest[]
    const memberRows = (members.data ?? []) as MemberRow[]
    const ids = Array.from(
      new Set([
        ...pendingRows.map((r) => r.user_id),
        ...memberRows.map((m) => m.user_id),
      ]),
    )
    const names: AdminData['names'] = {}
    if (ids.length > 0) {
      const profiles = await client
        .from('profiles')
        .select('user_id, display_name, organizational_title')
        .in('user_id', ids)
      if (profiles.error) return { ok: false, message: FAILED }
      for (const p of (profiles.data ?? []) as {
        user_id: string
        display_name: string
        organizational_title: string | null
      }[]) {
        names[p.user_id] = {
          display_name: p.display_name,
          organizational_title: p.organizational_title,
        }
      }
    }
    return {
      ok: true,
      data: {
        pending: pendingRows,
        members: memberRows,
        codes: (codes.data ?? []) as CodeRow[],
        names,
      },
    }
  } catch {
    return { ok: false, message: FAILED }
  }
}

async function call(
  client: SupabaseClient,
  fn: string,
  args: Record<string, unknown>,
): Promise<ActionResult & { raw?: unknown }> {
  try {
    const { data, error } = await client.rpc(fn, args)
    if (error) {
      if (error.code === '42501') return { ok: false, message: DENIED }
      if (error.code === '22023')
        return { ok: false, message: 'Check the values and try again.' }
      return { ok: false, message: FAILED }
    }
    const status = (data as { status?: string } | null)?.status ?? 'ok'
    return { ok: true, status, raw: data }
  } catch {
    return { ok: false, message: FAILED }
  }
}

export async function reviewRequest(
  client: SupabaseClient,
  requestId: string,
  decision: 'approve' | 'reject',
) {
  const r = await call(client, 'review_join_request', {
    p_request_id: requestId,
    p_decision: decision,
  })
  if (r.ok && r.status === 'not_pending')
    return { ok: false as const, message: 'That request was already handled.' }
  return r
}
export const suspendMember = (client: SupabaseClient, membershipId: string) =>
  call(client, 'suspend_member', { p_membership_id: membershipId })
export const reinstateMember = (client: SupabaseClient, membershipId: string) =>
  call(client, 'reinstate_member', { p_membership_id: membershipId })
export const revokeCode = (client: SupabaseClient, codeId: string) =>
  call(client, 'revoke_join_code', { p_code_id: codeId })

export type CreatedCode =
  { ok: true; code: string; expiresAt: string } | { ok: false; message: string }
export async function createCode(
  client: SupabaseClient,
  teamId: string,
  maxUses: number,
  validDays: number,
  label: string | null,
): Promise<CreatedCode> {
  const r = await call(client, 'create_join_code', {
    p_team_id: teamId,
    p_max_uses: maxUses,
    p_valid_days: validDays,
    p_label: label,
  })
  if (!r.ok) return r
  const raw = r.raw as { code?: string; expires_at?: string } | null
  if (!raw?.code) return { ok: false, message: FAILED }
  return { ok: true, code: raw.code, expiresAt: raw.expires_at ?? '' }
}
