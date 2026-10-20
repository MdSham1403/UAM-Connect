import { useEffect, useState, type FormEvent } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { validate, type FieldErrors } from '../auth/authSchemas'
import { Banner, Field, PrimaryButton } from '../auth/ui'
import { fetchOwnProfile, type Profile } from '../profile/profileApi'
import { redeemJoinCode } from './membershipApi'
import { joinSchema } from './membershipSchemas'

export function JoinScreen({
  wasRejected,
  onSubmitted,
}: {
  wasRejected: boolean
  onSubmitted: () => void
}) {
  const { client, user } = useAuth()
  const [profile, setProfile] = useState<Profile | null>(null)
  const [ready, setReady] = useState(false)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  useEffect(() => {
    let active = true
    void fetchOwnProfile(client, user?.id ?? '').then((r) => {
      if (!active) return
      if (r.ok) setProfile(r.profile)
      setReady(true)
    })
    return () => {
      active = false
    }
  }, [client, user?.id])

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const v = validate(
      joinSchema,
      Object.fromEntries(new FormData(e.currentTarget).entries()),
    )
    setFormError(null)
    if (!v.ok) return setErrors(v.errors)
    setErrors({})
    setPending(true)
    const r = await redeemJoinCode(client, {
      code: v.data.code,
      displayName: v.data.display_name,
      title: v.data.organizational_title,
    })
    setPending(false)
    if (r.ok) onSubmitted()
    else setFormError(r.message)
  }

  if (!ready) {
    return (
      <p role="status" className="text-gray-600">
        Loading…
      </p>
    )
  }
  return (
    <section className="flex flex-col gap-4" aria-labelledby="join-heading">
      <h2 id="join-heading" className="text-lg font-medium">
        Join your team
      </h2>
      <Banner kind="info">
        Signing in does not give access to team information. Enter the private
        joining code an administrator gave you. An administrator must then
        approve your request.
      </Banner>
      {wasRejected ? (
        <Banner kind="info">
          Your previous request was not approved. You can apply again with a new
          code.
        </Banner>
      ) : null}
      {formError ? <Banner kind="error">{formError}</Banner> : null}
      <form noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
        <Field
          label="Joining code"
          name="code"
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          error={errors.code}
        />
        <Field
          label="Your name"
          name="display_name"
          autoComplete="name"
          defaultValue={profile?.display_name ?? ''}
          error={errors.display_name}
        />
        <Field
          label="Organizational title (optional)"
          name="organizational_title"
          defaultValue={profile?.organizational_title ?? ''}
          error={errors.organizational_title}
        />
        <PrimaryButton pending={pending}>Request to join</PrimaryButton>
      </form>
    </section>
  )
}
