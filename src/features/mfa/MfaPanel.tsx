import { useEffect, useState, type FormEvent } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { Banner, Field, PrimaryButton } from '../auth/ui'
import {
  enrollTotp,
  findVerifiedTotpFactor,
  getAssurance,
  verifyTotp,
} from './mfaApi'

type Phase =
  | { kind: 'loading' }
  | { kind: 'error'; message: string }
  | { kind: 'verified' }
  | { kind: 'challenge'; factorId: string }
  | { kind: 'setup' }
  | { kind: 'enrolled'; factorId: string; qrCode: string; secret: string }

/** Authenticator-app (TOTP) enrolment and verification. Sensitive admin actions need aal2. */
export function MfaPanel({ onVerified }: { onVerified: () => void }) {
  const { client } = useAuth()
  const [phase, setPhase] = useState<Phase>({ kind: 'loading' })
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  useEffect(() => {
    let active = true
    void (async () => {
      const a = await getAssurance(client)
      if (!active) return
      if (!a.ok) return setPhase({ kind: 'error', message: a.message })
      if (a.level === 'aal2') {
        setPhase({ kind: 'verified' })
        return onVerified()
      }
      const f = await findVerifiedTotpFactor(client)
      if (!active) return
      if (!f.ok) return setPhase({ kind: 'error', message: f.message })
      setPhase(
        f.verifiedFactorId
          ? { kind: 'challenge', factorId: f.verifiedFactorId }
          : { kind: 'setup' },
      )
    })()
    return () => {
      active = false
    }
    // onVerified is intentionally not a dependency: the check runs once per mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [client])

  async function startSetup() {
    setError(null)
    setPending(true)
    const r = await enrollTotp(client)
    setPending(false)
    if (r.ok)
      setPhase({
        kind: 'enrolled',
        factorId: r.factorId,
        qrCode: r.qrCode,
        secret: r.secret,
      })
    else setError(r.message)
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>, factorId: string) {
    e.preventDefault()
    const code = String(
      new FormData(e.currentTarget).get('code') ?? '',
    ).replace(/\s/g, '')
    if (!/^\d{6}$/.test(code))
      return setError('Enter the 6-digit code from your authenticator app.')
    setError(null)
    setPending(true)
    const r = await verifyTotp(client, factorId, code)
    setPending(false)
    if (r.ok) {
      setPhase({ kind: 'verified' })
      onVerified()
    } else setError(r.message)
  }

  if (phase.kind === 'loading')
    return <p role="status">Checking verification…</p>
  if (phase.kind === 'error')
    return <Banner kind="error">{phase.message}</Banner>
  if (phase.kind === 'verified')
    return <Banner kind="info">Verified with your authenticator app.</Banner>

  const codeForm = (factorId: string) => (
    <form
      noValidate
      onSubmit={(e) => void onSubmit(e, factorId)}
      className="flex flex-col gap-3"
    >
      <Field
        label="6-digit code"
        name="code"
        inputMode="numeric"
        autoComplete="one-time-code"
      />
      <PrimaryButton pending={pending}>Verify</PrimaryButton>
    </form>
  )

  return (
    <section
      className="flex flex-col gap-3"
      aria-label="Verify with your authenticator app"
    >
      <Banner kind="info">
        Administrative changes require a code from your authenticator app.
        Reading is not affected.
      </Banner>
      {error ? <Banner kind="error">{error}</Banner> : null}
      {phase.kind === 'challenge' ? codeForm(phase.factorId) : null}
      {phase.kind === 'setup' ? (
        <PrimaryButton
          type="button"
          pending={pending}
          onClick={() => void startSetup()}
        >
          Set up authenticator app
        </PrimaryButton>
      ) : null}
      {phase.kind === 'enrolled' ? (
        <>
          <p className="text-sm">
            Scan this with an authenticator app, or enter the key by hand, then
            type the code it shows.
          </p>
          <img
            src={phase.qrCode}
            alt="QR code to add UAM Connect to your authenticator app"
            className="h-44 w-44"
          />
          <p className="text-sm break-all">
            Key: <code>{phase.secret}</code>
          </p>
          {codeForm(phase.factorId)}
        </>
      ) : null}
    </section>
  )
}
