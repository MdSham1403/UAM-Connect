import { useState, type FormEvent } from 'react'
import { useAuth } from './AuthProvider'
import { updatePassword } from './authApi'
import { resetSchema, validate, type FieldErrors } from './authSchemas'
import { Banner, Field, LinkButton, PrimaryButton } from './ui'

/** Shown in place of everything else while a password-recovery session is open. */
export function ResetPasswordScreen() {
  const { client, endRecovery, signOut } = useAuth()
  const [errors, setErrors] = useState<FieldErrors>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const v = validate(
      resetSchema,
      Object.fromEntries(new FormData(e.currentTarget).entries()),
    )
    setFormError(null)
    if (!v.ok) return setErrors(v.errors)
    setErrors({})
    setPending(true)
    const r = await updatePassword(client, v.data.password)
    setPending(false)
    if (r.ok) endRecovery()
    else setFormError(r.message)
  }

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">UAM Connect</h1>
      <h2 className="text-lg font-medium">Choose a new password</h2>
      {formError ? <Banner kind="error">{formError}</Banner> : null}
      <form noValidate onSubmit={onSubmit} className="flex flex-col gap-4">
        <Field
          label="New password"
          name="password"
          type="password"
          autoComplete="new-password"
          error={errors.password}
        />
        <Field
          label="Confirm new password"
          name="confirm"
          type="password"
          autoComplete="new-password"
          error={errors.confirm}
        />
        <p className="text-sm text-gray-600">
          At least 12 characters with upper-case, lower-case and a number.
        </p>
        <PrimaryButton pending={pending}>Save new password</PrimaryButton>
      </form>
      <LinkButton onClick={() => void signOut()}>
        Cancel and sign out
      </LinkButton>
    </main>
  )
}
