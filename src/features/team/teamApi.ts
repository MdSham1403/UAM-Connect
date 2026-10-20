import type { SupabaseClient } from '@supabase/supabase-js'

export interface RoleChip {
  id: string
  name: string
  is_primary: boolean
}
export interface DirectoryEntry {
  membership_id: string
  display_name: string
  organizational_title: string | null
  roles: RoleChip[]
}
export interface OperationalRole {
  id: string
  name: string
  description: string | null
  is_active: boolean
  member_count: number
}

export type Load<T> = { ok: true; value: T } | { ok: false; message: string }
export type Change =
  { ok: true; status: string } | { ok: false; message: string }

const LOAD_FAILED = 'Could not load this. Try again.'
const NETWORK = 'Cannot reach the server. Check your connection and try again.'

const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null

function parseChip(v: unknown): RoleChip | null {
  if (!isObj(v) || typeof v.id !== 'string' || typeof v.name !== 'string')
    return null
  return { id: v.id, name: v.name, is_primary: v.is_primary === true }
}

/** Ignores malformed entries instead of trusting the response shape. */
export function parseDirectory(data: unknown): DirectoryEntry[] | null {
  if (!Array.isArray(data)) return null
  const out: DirectoryEntry[] = []
  for (const e of data) {
    if (!isObj(e) || typeof e.membership_id !== 'string') continue
    out.push({
      membership_id: e.membership_id,
      display_name:
        typeof e.display_name === 'string' && e.display_name !== ''
          ? e.display_name
          : 'Unnamed member',
      organizational_title:
        typeof e.organizational_title === 'string'
          ? e.organizational_title
          : null,
      roles: (Array.isArray(e.roles) ? e.roles : [])
        .map(parseChip)
        .filter((c): c is RoleChip => c !== null),
    })
  }
  return out
}

export function parseRoles(data: unknown): OperationalRole[] | null {
  if (!Array.isArray(data)) return null
  const out: OperationalRole[] = []
  for (const r of data) {
    if (!isObj(r) || typeof r.id !== 'string' || typeof r.name !== 'string')
      continue
    out.push({
      id: r.id,
      name: r.name,
      description: typeof r.description === 'string' ? r.description : null,
      is_active: r.is_active !== false,
      member_count: typeof r.member_count === 'number' ? r.member_count : 0,
    })
  }
  return out
}

async function read<T>(
  client: SupabaseClient,
  fn: string,
  teamId: string,
  parse: (d: unknown) => T | null,
): Promise<Load<T>> {
  try {
    const { data, error } = await client.rpc(fn, { p_team_id: teamId })
    if (error) return { ok: false, message: LOAD_FAILED }
    const value = parse(data)
    return value === null
      ? { ok: false, message: LOAD_FAILED }
      : { ok: true, value }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export const getDirectory = (client: SupabaseClient, teamId: string) =>
  read(client, 'team_directory', teamId, parseDirectory)
export const listRoles = (client: SupabaseClient, teamId: string) =>
  read(client, 'list_operational_roles', teamId, parseRoles)

const STATUS_MESSAGES: Record<string, string> = {
  duplicate: 'A role with that name already exists.',
  role_inactive: 'That role is inactive. Reactivate it first.',
  not_approved: 'Only approved members can be given roles.',
}

/** Calls a change function; the server decides everything and reports a status. */
async function change(
  client: SupabaseClient,
  fn: string,
  args: Record<string, unknown>,
  okStatuses: string[],
): Promise<Change> {
  try {
    const { data, error } = await client.rpc(fn, args)
    if (error) {
      if (error.code === '42501') {
        return {
          ok: false,
          message:
            'Not permitted. Role changes need an administrator with a verified authenticator code.',
        }
      }
      if (error.code === '22023')
        return { ok: false, message: 'Check the values and try again.' }
      return { ok: false, message: 'Could not save the change. Try again.' }
    }
    const status =
      isObj(data) && typeof data.status === 'string' ? data.status : ''
    if (okStatuses.includes(status)) return { ok: true, status }
    return {
      ok: false,
      message:
        STATUS_MESSAGES[status] ?? 'Could not save the change. Try again.',
    }
  } catch {
    return { ok: false, message: NETWORK }
  }
}

export const createRole = (
  client: SupabaseClient,
  teamId: string,
  name: string,
  description: string | null,
) =>
  change(
    client,
    'create_operational_role',
    { p_team_id: teamId, p_name: name, p_description: description },
    ['created'],
  )

export const updateRole = (
  client: SupabaseClient,
  roleId: string,
  patch: { name?: string; description?: string; isActive?: boolean },
) => {
  const args: Record<string, unknown> = { p_role_id: roleId }
  if (patch.name !== undefined) args.p_name = patch.name
  if (patch.description !== undefined) args.p_description = patch.description
  if (patch.isActive !== undefined) args.p_is_active = patch.isActive
  return change(client, 'update_operational_role', args, ['updated'])
}

export const assignRole = (
  client: SupabaseClient,
  membershipId: string,
  roleId: string,
  isPrimary: boolean,
) =>
  change(
    client,
    'assign_operational_role',
    {
      p_membership_id: membershipId,
      p_role_id: roleId,
      p_is_primary: isPrimary,
    },
    ['assigned'],
  )

export const unassignRole = (
  client: SupabaseClient,
  membershipId: string,
  roleId: string,
) =>
  change(
    client,
    'unassign_operational_role',
    { p_membership_id: membershipId, p_role_id: roleId },
    ['unassigned', 'not_assigned'],
  )
