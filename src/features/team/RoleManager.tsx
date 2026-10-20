import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { Banner, Field, PrimaryButton } from '../auth/ui'
import {
  assignRole,
  createRole,
  getDirectory,
  listRoles,
  unassignRole,
  updateRole,
  type Change,
  type DirectoryEntry,
  type OperationalRole,
} from './teamApi'

/**
 * Operational-role administration. Buttons are enabled only after authenticator verification as a
 * convenience; the database refuses every change without it regardless.
 */
export function RoleManager({
  teamId,
  aal2,
  onChanged,
}: {
  teamId: string
  aal2: boolean
  onChanged?: () => void
}) {
  const { client } = useAuth()
  const [roles, setRoles] = useState<OperationalRole[]>([])
  const [members, setMembers] = useState<DirectoryEntry[]>([])
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const reload = useCallback(async () => {
    const [r, d] = await Promise.all([
      listRoles(client, teamId),
      getDirectory(client, teamId),
    ])
    if (r.ok) setRoles(r.value)
    if (d.ok) setMembers(d.value)
    if (!r.ok) setError(r.message)
    else if (!d.ok) setError(d.message)
  }, [client, teamId])

  useEffect(() => {
    void reload()
  }, [reload])

  async function act(run: () => Promise<Change>, done: string) {
    setError(null)
    setNotice(null)
    setBusy(true)
    const r = await run()
    setBusy(false)
    if (r.ok) {
      setNotice(done)
      await reload()
      onChanged?.()
    } else setError(r.message)
  }

  function onCreate(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = e.currentTarget
    const f = new FormData(form)
    const name = String(f.get('new_role_name') ?? '').trim()
    const description = String(f.get('new_role_description') ?? '').trim()
    if (name === '' || name.length > 60)
      return setError('Role names must be 1 to 60 characters.')
    if (description.length > 200)
      return setError('Descriptions can be at most 200 characters.')
    void act(
      () =>
        createRole(
          client,
          teamId,
          name,
          description === '' ? null : description,
        ),
      'Role created.',
    ).then(() => form.reset())
  }

  function onAssign(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    const membership = String(f.get('membership') ?? '')
    const role = String(f.get('role') ?? '')
    if (membership === '' || role === '')
      return setError('Choose a member and a role.')
    void act(
      () => assignRole(client, membership, role, f.get('primary') === 'on'),
      'Role assigned.',
    )
  }

  const disabled = busy || !aal2
  const active = roles.filter((r) => r.is_active)
  return (
    <section className="flex flex-col gap-4" aria-labelledby="roles-heading">
      <h3 id="roles-heading" className="font-medium">
        Operational roles
      </h3>
      {!aal2 ? (
        <Banner kind="info">
          Verify your authenticator code above to change roles.
        </Banner>
      ) : null}
      {notice ? <Banner kind="info">{notice}</Banner> : null}
      {error ? <Banner kind="error">{error}</Banner> : null}

      <form
        noValidate
        onSubmit={onCreate}
        className="flex flex-col gap-3"
        aria-label="Create operational role"
      >
        <Field label="New role name" name="new_role_name" autoComplete="off" />
        <Field
          label="Description (optional)"
          name="new_role_description"
          autoComplete="off"
        />
        <PrimaryButton pending={busy} disabled={disabled}>
          Add role
        </PrimaryButton>
      </form>

      <ul className="flex flex-col gap-3">
        {roles.map((r) => (
          <li
            key={r.id}
            className="flex flex-col gap-2 rounded-md border border-gray-200 p-3"
          >
            <form
              noValidate
              aria-label={`Edit ${r.name}`}
              className="flex flex-wrap items-end gap-2"
              onSubmit={(e) => {
                e.preventDefault()
                const name = String(
                  new FormData(e.currentTarget).get(`role_name_${r.id}`) ?? '',
                ).trim()
                if (name === '' || name.length > 60)
                  return setError('Role names must be 1 to 60 characters.')
                void act(
                  () => updateRole(client, r.id, { name }),
                  'Role renamed.',
                )
              }}
            >
              <Field
                label={r.is_active ? 'Role name' : 'Role name (inactive)'}
                name={`role_name_${r.id}`}
                defaultValue={r.name}
                autoComplete="off"
              />
              <button
                type="submit"
                disabled={disabled}
                className="min-h-11 underline disabled:opacity-50"
              >
                Save name
              </button>
              <button
                type="button"
                disabled={disabled}
                className="min-h-11 underline disabled:opacity-50"
                onClick={() =>
                  void act(
                    () => updateRole(client, r.id, { isActive: !r.is_active }),
                    r.is_active ? 'Role deactivated.' : 'Role reactivated.',
                  )
                }
              >
                {r.is_active ? `Deactivate ${r.name}` : `Reactivate ${r.name}`}
              </button>
            </form>
            <span className="text-sm text-gray-600">
              {r.member_count} member{r.member_count === 1 ? '' : 's'}
              {r.description ? ` · ${r.description}` : ''}
            </span>
          </li>
        ))}
      </ul>

      <h3 className="font-medium">Assign roles</h3>
      <form
        noValidate
        onSubmit={onAssign}
        className="flex flex-col gap-3"
        aria-label="Assign operational role"
      >
        <label className="flex flex-col gap-1 text-sm font-medium">
          Member
          <select
            name="membership"
            defaultValue=""
            className="min-h-11 rounded-md border border-gray-300 px-3 py-2 text-base"
          >
            <option value="" disabled>
              Choose a member
            </option>
            {members.map((m) => (
              <option key={m.membership_id} value={m.membership_id}>
                {m.display_name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm font-medium">
          Role
          <select
            name="role"
            defaultValue=""
            className="min-h-11 rounded-md border border-gray-300 px-3 py-2 text-base"
          >
            <option value="" disabled>
              Choose a role
            </option>
            {active.map((r) => (
              <option key={r.id} value={r.id}>
                {r.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex min-h-11 items-center gap-2 text-sm">
          <input type="checkbox" name="primary" /> Make this their primary role
        </label>
        <PrimaryButton pending={busy} disabled={disabled}>
          Assign role
        </PrimaryButton>
      </form>

      <ul className="flex flex-col gap-2">
        {members
          .filter((m) => m.roles.length > 0)
          .map((m) => (
            <li key={m.membership_id} className="flex flex-col gap-1 text-sm">
              <span className="font-medium">{m.display_name}</span>
              <span className="flex flex-wrap gap-2">
                {m.roles.map((r) => (
                  <span
                    key={r.id}
                    className="flex items-center gap-1 rounded-full border border-gray-300 px-2 py-0.5"
                  >
                    {r.name}
                    {r.is_primary ? ' (primary)' : ''}
                    <button
                      type="button"
                      disabled={disabled}
                      aria-label={`Remove ${r.name} from ${m.display_name}`}
                      className="min-h-6 min-w-6 disabled:opacity-50"
                      onClick={() =>
                        void act(
                          () => unassignRole(client, m.membership_id, r.id),
                          'Role removed.',
                        )
                      }
                    >
                      ×
                    </button>
                  </span>
                ))}
              </span>
            </li>
          ))}
      </ul>
    </section>
  )
}
