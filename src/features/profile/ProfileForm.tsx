import { useEffect, useState, type FormEvent } from 'react'
import { useAuth } from '../auth/AuthProvider'
import { profileSchema, validate, type FieldErrors } from '../auth/authSchemas'
import { Banner, Field, PrimaryButton } from '../auth/ui'
import { fetchOwnProfile, saveOwnProfile, type Profile } from './profileApi'

export function ProfileForm() {
  const { client, user } = useAuth()
  const userId = user?.id ?? ''
  const [loaded, setLoaded] = useState(false)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [errors, setErrors] = useState<FieldErrors>({})
  const [message, setMessage] = useState<{
    kind: 'error' | 'info'
    text: string
  } | null>(null)
  const [pending, setPending] = useState(false)

  useEffect(() => {
    let active = true
    void fetchOwnProfile(client, userId).then((r) => {
      if (!active) return
      if (r.ok) setProfile(r.profile)
      else setMessage({ kind: 'error', text: r.message })
      setLoaded(true)
    })
    return () => {
      active = false
    }
  }, [client, userId])

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const v = validate(
      profileSchema,
      Object.fromEntries(new FormData(e.currentTarget).entries()),
    )
    setMessage(null)
    if (!v.ok) return setErrors(v.errors)
    setErrors({})
    setPending(true)
    const r = await saveOwnProfile(client, userId, v.data, profile !== null)
    setPending(false)
    if (r.ok) {
      setProfile(v.data)
      setMessage({ kind: 'info', text: 'Profile saved.' })
    } else setMessage({ kind: 'error', text: r.message })
  }

  if (!loaded)
    return (
      <p role="status" className="text-gray-600">
        Loading profile…
      </p>
    )
  return (
    <form
      noValidate
      onSubmit={onSubmit}
      className="flex flex-col gap-4"
      aria-label="Your profile"
    >
      {message ? <Banner kind={message.kind}>{message.text}</Banner> : null}
      <Field
        label="Display name"
        name="display_name"
        defaultValue={profile?.display_name ?? ''}
        autoComplete="name"
        error={errors.display_name}
      />
      <Field
        label="Organizational title (optional)"
        name="organizational_title"
        defaultValue={profile?.organizational_title ?? ''}
        error={errors.organizational_title}
      />
      <PrimaryButton pending={pending}>Save profile</PrimaryButton>
    </form>
  )
}
