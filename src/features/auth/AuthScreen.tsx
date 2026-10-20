import { useState, type FormEvent } from 'react'
import { useAuth } from './AuthProvider'
import {
  requestPasswordReset,
  RESET_NOTICE,
  signIn,
  signUp,
  SIGN_UP_NOTICE,
} from './authApi'
import {
  forgotSchema,
  signInSchema,
  signUpSchema,
  validate,
  type FieldErrors,
} from './authSchemas'
import { redirectFor } from './flow'
import { Banner, Field, LinkButton, PrimaryButton } from './ui'

type Mode = 'signin' | 'signup' | 'forgot'

export function AuthScreen() {
  const { client, notice, clearNotice } = useAuth()
  const [mode, setMode] = useState<Mode>('signin')
  const [errors, setErrors] = useState<FieldErrors>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [info, setInfo] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  function switchMode(next: Mode) {
    setMode(next)
    setErrors({})
    setFormError(null)
    setInfo(null)
    clearNotice()
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const form = new FormData(e.currentTarget)
    const raw = Object.fromEntries(form.entries())
    setFormError(null)
    setInfo(null)
    setErrors({})

    if (mode === 'signin') {
      const v = validate(signInSchema, raw)
      if (!v.ok) return setErrors(v.errors)
      setPending(true)
      const r = await signIn(client, v.data.email, v.data.password)
      setPending(false)
      if (!r.ok) setFormError(r.message)
      return
    }
    if (mode === 'signup') {
      const v = validate(signUpSchema, raw)
      if (!v.ok) return setErrors(v.errors)
      setPending(true)
      const r = await signUp(
        client,
        v.data.email,
        v.data.password,
        redirectFor('confirm'),
      )
      setPending(false)
      if (r.ok) setInfo(SIGN_UP_NOTICE)
      else setFormError(r.message)
      return
    }
    const v = validate(forgotSchema, raw)
    if (!v.ok) return setErrors(v.errors)
    setPending(true)
    const r = await requestPasswordReset(
      client,
      v.data.email,
      redirectFor('recovery'),
    )
    setPending(false)
    if (r.ok) setInfo(RESET_NOTICE)
    else setFormError(r.message)
  }

  const title =
    mode === 'signin'
      ? 'Sign in'
      : mode === 'signup'
        ? 'Create account'
        : 'Reset password'
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">UAM Connect</h1>
      <h2 className="text-lg font-medium">{title}</h2>
      {notice ? <Banner kind="info">{notice}</Banner> : null}
      {info ? <Banner kind="info">{info}</Banner> : null}
      {formError ? <Banner kind="error">{formError}</Banner> : null}
      <form
        noValidate
        onSubmit={onSubmit}
        className="flex flex-col gap-4"
        key={mode}
      >
        <Field
          label="Email"
          name="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          error={errors.email}
        />
        {mode !== 'forgot' ? (
          <Field
            label="Password"
            name="password"
            type="password"
            autoComplete={
              mode === 'signin' ? 'current-password' : 'new-password'
            }
            error={errors.password}
          />
        ) : null}
        {mode === 'signup' ? (
          <Field
            label="Confirm password"
            name="confirm"
            type="password"
            autoComplete="new-password"
            error={errors.confirm}
          />
        ) : null}
        {mode === 'signup' ? (
          <p className="text-sm text-gray-600">
            At least 12 characters with upper-case, lower-case and a number.
          </p>
        ) : null}
        <PrimaryButton pending={pending}>{title}</PrimaryButton>
      </form>
      <div className="flex flex-wrap gap-x-4">
        {mode !== 'signin' ? (
          <LinkButton onClick={() => switchMode('signin')}>
            Back to sign in
          </LinkButton>
        ) : null}
        {mode === 'signin' ? (
          <LinkButton onClick={() => switchMode('signup')}>
            Create account
          </LinkButton>
        ) : null}
        {mode === 'signin' ? (
          <LinkButton onClick={() => switchMode('forgot')}>
            Forgot password?
          </LinkButton>
        ) : null}
      </div>
      <p className="text-xs text-gray-600">
        Creating an account does not give access to team information. Access
        requires a private joining code and administrator approval.
      </p>
    </main>
  )
}
