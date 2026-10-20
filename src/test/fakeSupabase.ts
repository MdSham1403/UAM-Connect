import { vi } from 'vitest'
import type {
  AuthChangeEvent,
  AuthError,
  Session,
  SupabaseClient,
} from '@supabase/supabase-js'

export function makeSession(
  email = 'member@example.invalid',
  id = 'user-1',
): Session {
  return {
    access_token: 'test-access',
    refresh_token: 'test-refresh',
    expires_in: 3600,
    token_type: 'bearer',
    user: {
      id,
      email,
      aud: 'authenticated',
      app_metadata: {},
      user_metadata: {},
      created_at: '2026-01-01T00:00:00Z',
    },
  } as unknown as Session
}

export function authError(
  code: string,
  status = 400,
  name = 'AuthApiError',
): AuthError {
  return Object.assign(new Error(code), {
    name,
    status,
    code,
  }) as unknown as AuthError
}

type MembershipRow = {
  id: string
  team_id: string
  membership_status: string
} | null

type Listener = (event: AuthChangeEvent, session: Session | null) => void

/**
 * A hand-written stand-in for the Supabase client. Tests that use it are MOCKED tests:
 * they prove how our code reacts to Supabase responses, not how real Supabase behaves.
 */
export function createFakeClient(
  opts: {
    session?: Session | null
    profile?: {
      display_name: string
      organizational_title: string | null
    } | null
    membership?: MembershipRow
    teamName?: string | null
  } = {},
) {
  let listener: Listener | null = null
  const calls = {
    from: [] as string[],
    insert: [] as unknown[],
    update: [] as unknown[],
    order: [] as string[],
  }
  const profileState = {
    row: opts.profile ?? null,
    selectError: null as unknown,
    writeError: null as unknown,
  }
  const membershipState = {
    row: (opts.membership ?? null) as MembershipRow,
    error: null as unknown,
  }
  const teamState = { name: opts.teamName ?? null }

  const auth = {
    getSession: vi.fn(async () => ({
      data: { session: opts.session ?? null },
      error: null,
    })),
    onAuthStateChange: vi.fn((cb: Listener) => {
      listener = cb
      return { data: { subscription: { unsubscribe: vi.fn() } } }
    }),
    signInWithPassword: vi.fn(async () => ({ data: {}, error: null })),
    signUp: vi.fn(async () => ({
      data: { user: { id: 'new' }, session: null },
      error: null,
    })),
    signOut: vi.fn(async () => ({ error: null })),
    resetPasswordForEmail: vi.fn(async () => ({ data: {}, error: null })),
    updateUser: vi.fn(async () => ({ data: {}, error: null })),
    verifyOtp: vi.fn(async () => ({ data: {}, error: null })),
    mfa: {
      getAuthenticatorAssuranceLevel: vi.fn(async () => ({
        data: { currentLevel: 'aal1', nextLevel: 'aal1' },
        error: null,
      })),
      listFactors: vi.fn(async () => ({
        data: { all: [], totp: [] },
        error: null,
      })),
      enroll: vi.fn(async () => ({
        data: {
          id: 'factor-1',
          type: 'totp',
          totp: {
            qr_code: 'data:image/svg+xml;utf8,<svg/>',
            secret: 'SECRETKEY',
            uri: 'otpauth://x',
          },
        },
        error: null,
      })),
      challengeAndVerify: vi.fn(async () => ({ data: {}, error: null })),
    },
  }

  // Rows returned when a query is awaited without .maybeSingle() (admin lists).
  const lists: Record<string, unknown[]> = {}
  const listError = { value: null as unknown }

  const from = vi.fn((table: string) => {
    calls.from.push(table)
    const builder = {
      select: () => builder,
      eq: () => builder,
      in: () => builder,
      order: (column: string) => {
        calls.order.push(`${table}.${column}`)
        return builder
      },
      maybeSingle: async () => {
        if (table === 'team_memberships')
          return { data: membershipState.row, error: membershipState.error }
        if (table === 'teams')
          return {
            data: teamState.name ? { id: 't', name: teamState.name } : null,
            error: null,
          }
        return { data: profileState.row, error: profileState.selectError }
      },
      then: (resolve: (v: { data: unknown[]; error: unknown }) => unknown) =>
        resolve({ data: lists[table] ?? [], error: listError.value }),
      insert: async (row: unknown) => {
        calls.insert.push(row)
        return { error: profileState.writeError }
      },
      update: (row: unknown) => {
        calls.update.push(row)
        return { eq: async () => ({ error: profileState.writeError }) }
      },
    }
    return builder
  })

  const rpc = vi.fn(
    async (
      name: string,
      ..._args: unknown[]
    ): Promise<{ data: unknown; error: unknown }> => ({
      data:
        name === 'team_directory' || name === 'list_operational_roles'
          ? []
          : { status: 'pending' },
      error: null,
    }),
  )

  return {
    client: { auth, from, rpc } as unknown as SupabaseClient,
    auth,
    from,
    rpc,
    lists,
    listError,
    calls,
    profileState,
    membershipState,
    teamState,
    emit: (event: AuthChangeEvent, session: Session | null) =>
      listener?.(event, session),
  }
}
