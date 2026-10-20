import type { SupabaseClient } from '@supabase/supabase-js'

export type MembershipStatus =
  'pending' | 'approved' | 'rejected' | 'suspended' | 'removed'

export interface Membership {
  id: string
  team_id: string
  membership_status: MembershipStatus
}

export type MembershipLoad =
  { ok: true; membership: Membership | null } | { ok: false; message: string }

const LOAD_FAILED = 'Could not load your membership status. Try again.'

/**
 * Read the signed-in user's own membership row. Row Level Security returns only their own
 * row, and only the granted columns. This is display data: it never grants anything.
 */
export async function fetchMyMembership(
  client: SupabaseClient,
  userId: string,
): Promise<MembershipLoad> {
  try {
    const { data, error } = await client
      .from('team_memberships')
      .select('id, team_id, membership_status')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) return { ok: false, message: LOAD_FAILED }
    return { ok: true, membership: (data as Membership | null) ?? null }
  } catch {
    return { ok: false, message: LOAD_FAILED }
  }
}

/** Approved members only: the database returns no row to anyone else. */
export async function fetchTeamName(
  client: SupabaseClient,
  teamId: string,
): Promise<string | null> {
  try {
    const { data, error } = await client
      .from('teams')
      .select('id, name')
      .eq('id', teamId)
      .maybeSingle()
    if (error || !data) return null
    return (data as { name: string }).name
  } catch {
    return null
  }
}

export type RedeemOutcome =
  | { ok: true; status: 'pending' | 'already_pending' | 'already_member' }
  | { ok: false; message: string }

const REDEEM_MESSAGES: Record<string, string> = {
  invalid_code:
    'That code is not valid. Check it, or ask an administrator for a new one.',
  rate_limited:
    'Too many unsuccessful attempts. Wait about 15 minutes and try again.',
  blocked: 'Your access is restricted. Contact an administrator.',
}

/** Redeem a joining code. The server decides everything; the client only reports the result. */
export async function redeemJoinCode(
  client: SupabaseClient,
  input: { code: string; displayName: string; title: string | null },
): Promise<RedeemOutcome> {
  try {
    const { data, error } = await client.rpc('redeem_join_code', {
      p_code: input.code,
      p_display_name: input.displayName,
      p_title: input.title,
    })
    if (error) {
      if (error.code === '42501') {
        return {
          ok: false,
          message:
            'Confirm your email address, then sign out and sign in again.',
        }
      }
      if (error.code === '22023')
        return {
          ok: false,
          message: 'Check your name and title and try again.',
        }
      return { ok: false, message: 'Could not submit the code. Try again.' }
    }
    const status = (data as { status?: string } | null)?.status ?? ''
    if (
      status === 'pending' ||
      status === 'already_pending' ||
      status === 'already_member'
    ) {
      return { ok: true, status }
    }
    return {
      ok: false,
      message:
        REDEEM_MESSAGES[status] ?? 'Could not submit the code. Try again.',
    }
  } catch {
    return {
      ok: false,
      message: 'Cannot reach the server. Check your connection and try again.',
    }
  }
}
