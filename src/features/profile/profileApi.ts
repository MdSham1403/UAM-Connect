import type { SupabaseClient } from '@supabase/supabase-js'

export interface Profile {
  display_name: string
  organizational_title: string | null
}

export type ProfileLoad =
  { ok: true; profile: Profile | null } | { ok: false; message: string }
export type ProfileSave = { ok: true } | { ok: false; message: string }

const FAILED = 'Could not reach your profile. Try again.'

/** Read the signed-in user's own profile. Row Level Security limits this to their own row. */
export async function fetchOwnProfile(
  client: SupabaseClient,
  userId: string,
): Promise<ProfileLoad> {
  try {
    const { data, error } = await client
      .from('profiles')
      .select('display_name, organizational_title')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) return { ok: false, message: FAILED }
    return { ok: true, profile: (data as Profile | null) ?? null }
  } catch {
    return { ok: false, message: FAILED }
  }
}

/**
 * Create or update the user's own profile. Only display_name and organizational_title are
 * ever sent. Insert and update are separate calls because an upsert would also try to
 * update user_id, which clients are not allowed to change.
 */
export async function saveOwnProfile(
  client: SupabaseClient,
  userId: string,
  values: Profile,
  exists: boolean,
): Promise<ProfileSave> {
  try {
    const { error } = exists
      ? await client
          .from('profiles')
          .update({
            display_name: values.display_name,
            organizational_title: values.organizational_title,
          })
          .eq('user_id', userId)
      : await client.from('profiles').insert({
          user_id: userId,
          display_name: values.display_name,
          organizational_title: values.organizational_title,
        })
    return error
      ? {
          ok: false,
          message:
            'Could not save your profile. Check the values and try again.',
        }
      : { ok: true }
  } catch {
    return { ok: false, message: FAILED }
  }
}
