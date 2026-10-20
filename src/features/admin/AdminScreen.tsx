import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { Banner, Field, PrimaryButton } from '../auth/ui'
import { getAssurance } from '../mfa/mfaApi'
import { MfaPanel } from '../mfa/MfaPanel'
import {
  createCode,
  loadAdminData,
  reinstateMember,
  reviewRequest,
  revokeCode,
  suspendMember,
  type AdminData,
  type Access,
} from './adminApi'

function when(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString()
}

/**
 * Minimal administration. Buttons are enabled only after authenticator verification as a
 * convenience; the database refuses every sensitive action without it regardless.
 */
export function AdminScreen({
  teamId,
  access,
  onAssurance,
}: {
  teamId: string
  access: Access
  onAssurance?: (aal2: boolean) => void
}) {
  const { client, user } = useAuth()
  const [aal2, setAal2] = useState(false)
  const [data, setData] = useState<AdminData | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [newCode, setNewCode] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const reload = useCallback(async () => {
    const r = await loadAdminData(client, teamId)
    if (r.ok) setData(r.data)
    else setError(r.message)
  }, [client, teamId])

  useEffect(() => {
    void reload()
    void getAssurance(client).then((a) => {
      if (!a.ok) return
      setAal2(a.level === 'aal2')
      onAssurance?.(a.level === 'aal2')
    })
  }, [client, reload, onAssurance])

  async function act(
    run: () => Promise<
      { ok: true; status: string } | { ok: false; message: string }
    >,
    done: string,
  ) {
    setError(null)
    setNotice(null)
    setBusy(true)
    const r = await run()
    setBusy(false)
    if (r.ok) {
      setNotice(done)
      await reload()
    } else setError(r.message)
  }

  async function onCreate(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    const maxUses = Number(f.get('max_uses'))
    const days = Number(f.get('valid_days'))
    const label = String(f.get('label') ?? '').trim()
    if (!Number.isInteger(maxUses) || maxUses < 1 || maxUses > 50)
      return setError('Uses must be between 1 and 50.')
    if (!Number.isInteger(days) || days < 1 || days > 30)
      return setError('Validity must be between 1 and 30 days.')
    setError(null)
    setNotice(null)
    setNewCode(null)
    setBusy(true)
    const r = await createCode(
      client,
      teamId,
      maxUses,
      days,
      label === '' ? null : label,
    )
    setBusy(false)
    if (r.ok) {
      setNewCode(r.code)
      await reload()
    } else setError(r.message)
  }

  const can = (p: string) => access.superadmin || access.permissions.includes(p)
  const nameOf = (id: string) => data?.names[id]?.display_name ?? 'Unnamed user'
  const disabled = busy || !aal2

  return (
    <section className="flex flex-col gap-5" aria-labelledby="admin-heading">
      <h2 id="admin-heading" className="text-lg font-medium">
        Administration{access.superadmin ? ' (Superadmin)' : ''}
      </h2>
      {!aal2 ? (
        <MfaPanel
          onVerified={() => {
            setAal2(true)
            onAssurance?.(true)
          }}
        />
      ) : null}
      {error ? <Banner kind="error">{error}</Banner> : null}
      {notice ? <Banner kind="info">{notice}</Banner> : null}

      {can('join_codes.manage') ? (
        <div className="flex flex-col gap-3">
          <h3 className="font-medium">Joining codes</h3>
          <form
            noValidate
            onSubmit={(e) => void onCreate(e)}
            className="flex flex-col gap-3"
            aria-label="Create joining code"
          >
            <Field
              label="Number of uses"
              name="max_uses"
              type="number"
              defaultValue="1"
              min={1}
              max={50}
            />
            <Field
              label="Valid for (days)"
              name="valid_days"
              type="number"
              defaultValue="7"
              min={1}
              max={30}
            />
            <Field label="Label (optional)" name="label" maxLength={100} />
            <PrimaryButton pending={busy} disabled={disabled}>
              Create code
            </PrimaryButton>
          </form>
          {newCode ? (
            <Banner kind="info">
              Copy this code now and share it privately. It will not be shown
              again: <code>{newCode}</code>
            </Banner>
          ) : null}
          <ul className="flex flex-col gap-2">
            {(data?.codes ?? []).map((c) => {
              const expired = new Date(c.expires_at).getTime() < Date.now()
              const active =
                !c.revoked_at && !expired && c.use_count < c.max_uses
              return (
                <li
                  key={c.id}
                  className="flex flex-wrap items-center justify-between gap-2 text-sm"
                >
                  <span>
                    {c.label ?? 'Code'}: {c.use_count}/{c.max_uses} used,
                    expires {when(c.expires_at)}{' '}
                    {c.revoked_at
                      ? '(revoked)'
                      : expired
                        ? '(expired)'
                        : !active
                          ? '(used up)'
                          : ''}
                  </span>
                  {active ? (
                    <button
                      type="button"
                      disabled={disabled}
                      className="min-h-11 underline disabled:opacity-50"
                      onClick={() =>
                        void act(
                          () => revokeCode(client, c.id),
                          'Code revoked.',
                        )
                      }
                    >
                      Revoke
                    </button>
                  ) : null}
                </li>
              )
            })}
          </ul>
        </div>
      ) : null}

      {can('members.review') ? (
        <div className="flex flex-col gap-3">
          <h3 className="font-medium">Pending requests</h3>
          {data && data.pending.length === 0 ? (
            <p className="text-sm text-gray-600">No pending requests.</p>
          ) : null}
          <ul className="flex flex-col gap-2">
            {(data?.pending ?? []).map((r) => (
              <li
                key={r.id}
                className="flex flex-wrap items-center justify-between gap-2"
              >
                <span className="text-sm">
                  {nameOf(r.user_id)}
                  {data?.names[r.user_id]?.organizational_title
                    ? `, ${data.names[r.user_id].organizational_title}`
                    : ''}{' '}
                  <span className="text-gray-600">
                    requested {when(r.requested_at)}
                  </span>
                </span>
                <span className="flex gap-3">
                  <button
                    type="button"
                    disabled={disabled}
                    className="min-h-11 underline disabled:opacity-50"
                    onClick={() =>
                      void act(
                        () => reviewRequest(client, r.id, 'approve'),
                        'Request approved.',
                      )
                    }
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    disabled={disabled}
                    className="min-h-11 underline disabled:opacity-50"
                    onClick={() =>
                      void act(
                        () => reviewRequest(client, r.id, 'reject'),
                        'Request rejected.',
                      )
                    }
                  >
                    Reject
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {can('members.review') ? (
        <div className="flex flex-col gap-3">
          <h3 className="font-medium">Members</h3>
          <ul className="flex flex-col gap-2">
            {[...(data?.members ?? [])]
              .sort((a, b) =>
                nameOf(a.user_id).localeCompare(nameOf(b.user_id)),
              )
              .map((m) => (
                <li
                  key={m.id}
                  className="flex flex-wrap items-center justify-between gap-2 text-sm"
                >
                  <span>
                    {nameOf(m.user_id)}{' '}
                    <span className="text-gray-600">
                      ({m.membership_status})
                    </span>
                  </span>
                  {can('members.suspend') &&
                  m.user_id !== user?.id &&
                  m.membership_status === 'approved' ? (
                    <button
                      type="button"
                      disabled={disabled}
                      className="min-h-11 underline disabled:opacity-50"
                      onClick={() =>
                        void act(
                          () => suspendMember(client, m.id),
                          'Member suspended.',
                        )
                      }
                    >
                      Suspend
                    </button>
                  ) : null}
                  {can('members.suspend') &&
                  m.user_id !== user?.id &&
                  m.membership_status === 'suspended' ? (
                    <button
                      type="button"
                      disabled={disabled}
                      className="min-h-11 underline disabled:opacity-50"
                      onClick={() =>
                        void act(
                          () => reinstateMember(client, m.id),
                          'Member reinstated.',
                        )
                      }
                    >
                      Reinstate
                    </button>
                  ) : null}
                </li>
              ))}
          </ul>
        </div>
      ) : null}
    </section>
  )
}
