import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { Banner, LinkButton } from '../auth/ui'
import { AdminSection } from '../admin/AdminSection'
import { TeamDirectory } from '../team/TeamDirectory'
import { ProfileForm } from '../profile/ProfileForm'
import { JoinScreen } from './JoinScreen'
import {
  fetchMyMembership,
  fetchTeamName,
  type Membership,
} from './membershipApi'

type State =
  | { kind: 'loading' }
  | { kind: 'error'; message: string }
  | { kind: 'ready'; membership: Membership | null }

/**
 * Chooses what a signed-in user sees from their OWN membership row. This is presentation
 * only: the database decides what data anyone may read, whatever this component renders.
 */
export function MembershipGate() {
  const { client, user } = useAuth()
  const userId = user?.id ?? ''
  const [state, setState] = useState<State>({ kind: 'loading' })
  const [teamName, setTeamName] = useState<string | null>(null)

  const load = useCallback(async () => {
    setState({ kind: 'loading' })
    const r = await fetchMyMembership(client, userId)
    setState(
      r.ok
        ? { kind: 'ready', membership: r.membership }
        : { kind: 'error', message: r.message },
    )
  }, [client, userId])

  useEffect(() => {
    void load()
  }, [load])

  const approvedTeamId =
    state.kind === 'ready' && state.membership?.membership_status === 'approved'
      ? state.membership.team_id
      : null
  useEffect(() => {
    if (!approvedTeamId) return
    let active = true
    void fetchTeamName(client, approvedTeamId).then(
      (n) => active && setTeamName(n),
    )
    return () => {
      active = false
    }
  }, [client, approvedTeamId])

  if (state.kind === 'loading') {
    return (
      <p role="status" className="text-gray-600">
        Loading…
      </p>
    )
  }
  if (state.kind === 'error') {
    return (
      <div className="flex flex-col gap-2">
        <Banner kind="error">{state.message}</Banner>
        <LinkButton onClick={() => void load()}>Try again</LinkButton>
      </div>
    )
  }

  const m = state.membership
  const status = m?.membership_status ?? null

  if (status === null || status === 'rejected') {
    return (
      <JoinScreen
        wasRejected={status === 'rejected'}
        onSubmitted={() => void load()}
      />
    )
  }
  if (status === 'pending') {
    return (
      <section
        className="flex flex-col gap-3"
        aria-labelledby="pending-heading"
      >
        <h2 id="pending-heading" className="text-lg font-medium">
          Waiting for approval
        </h2>
        <Banner kind="info">
          Your request was sent. An administrator needs to approve it before you
          can see team information.
        </Banner>
        <LinkButton onClick={() => void load()}>Check status</LinkButton>
      </section>
    )
  }
  if (status === 'approved') {
    return (
      <section className="flex flex-col gap-4" aria-labelledby="member-heading">
        <h2 id="member-heading" className="text-lg font-medium">
          {teamName ? `Welcome to ${teamName}` : 'Welcome to your team'}
        </h2>
        <Banner kind="info">
          You are an approved member. Team features arrive in the next phases.
        </Banner>
        {m ? <TeamDirectory teamId={m.team_id} /> : null}
        <h3 className="font-medium">Your profile</h3>
        <ProfileForm />
        {m ? <AdminSection teamId={m.team_id} /> : null}
      </section>
    )
  }
  return (
    <section
      className="flex flex-col gap-3"
      aria-labelledby="restricted-heading"
    >
      <h2 id="restricted-heading" className="text-lg font-medium">
        Access restricted
      </h2>
      <Banner kind="error">
        Your access to this team is restricted. Contact an administrator.
      </Banner>
    </section>
  )
}
