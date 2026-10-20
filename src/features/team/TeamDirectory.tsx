import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { Banner, LinkButton } from '../auth/ui'
import { getDirectory, type DirectoryEntry } from './teamApi'

export function RoleChips({ roles }: { roles: DirectoryEntry['roles'] }) {
  if (roles.length === 0)
    return <span className="text-sm text-gray-500">No operational roles</span>
  return (
    <ul className="flex flex-wrap gap-1" aria-label="Operational roles">
      {roles.map((r) => (
        <li
          key={r.id}
          className="rounded-full border border-gray-300 px-2 py-0.5 text-xs"
        >
          {r.name}
          {r.is_primary ? (
            <span className="ml-1 font-medium">(primary)</span>
          ) : null}
        </li>
      ))}
    </ul>
  )
}

/** Approved members only: the server refuses everyone else. */
export function TeamDirectory({
  teamId,
  refreshKey = 0,
}: {
  teamId: string
  refreshKey?: number
}) {
  const { client } = useAuth()
  const [entries, setEntries] = useState<DirectoryEntry[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  const load = useCallback(async () => {
    setError(null)
    const r = await getDirectory(client, teamId)
    if (r.ok) setEntries(r.value)
    else setError(r.message)
  }, [client, teamId])

  useEffect(() => {
    void load()
  }, [load, refreshKey])

  if (error) {
    return (
      <div className="flex flex-col gap-2">
        <Banner kind="error">{error}</Banner>
        <LinkButton onClick={() => void load()}>Try again</LinkButton>
      </div>
    )
  }
  if (!entries) {
    return (
      <p role="status" className="text-gray-600">
        Loading team…
      </p>
    )
  }
  const q = query.trim().toLowerCase()
  const shown = q
    ? entries.filter((e) =>
        [
          e.display_name,
          e.organizational_title ?? '',
          ...e.roles.map((r) => r.name),
        ]
          .join(' ')
          .toLowerCase()
          .includes(q),
      )
    : entries
  return (
    <section
      className="flex flex-col gap-3"
      aria-labelledby="directory-heading"
    >
      <h3 id="directory-heading" className="font-medium">
        Team directory
      </h3>
      <div className="flex flex-col gap-1">
        <label htmlFor="directory-search" className="text-sm font-medium">
          Search by name, title or role
        </label>
        <input
          id="directory-search"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="min-h-11 rounded-md border border-gray-300 px-3 py-2 text-base"
        />
      </div>
      {entries.length === 0 ? (
        <p className="text-sm text-gray-600">No members to show yet.</p>
      ) : null}
      {entries.length > 0 && shown.length === 0 ? (
        <p className="text-sm text-gray-600">No one matches that search.</p>
      ) : null}
      <ul className="flex flex-col gap-3">
        {shown.map((e) => (
          <li
            key={e.membership_id}
            className="flex flex-col gap-1 rounded-md border border-gray-200 p-3"
          >
            <span className="font-medium">{e.display_name}</span>
            {e.organizational_title ? (
              <span className="text-sm text-gray-600">
                {e.organizational_title}
              </span>
            ) : null}
            <RoleChips roles={e.roles} />
          </li>
        ))}
      </ul>
    </section>
  )
}
