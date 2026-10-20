import { z } from 'zod'

// Client-side validation is for usability only. Supabase Auth and the database enforce the
// real rules (see supabase/config.toml and SECURITY.md).

const email = z
  .string()
  .trim()
  .min(1, 'Enter your email address.')
  .max(254, 'Email address is too long.')
  .pipe(z.email('Enter a valid email address.'))

// bcrypt (used by Supabase Auth) only considers the first 72 bytes.
const newPassword = z
  .string()
  .min(12, 'Use at least 12 characters.')
  .max(72, 'Use at most 72 characters.')
  .refine((v) => /[a-z]/.test(v), 'Include a lowercase letter.')
  .refine((v) => /[A-Z]/.test(v), 'Include an uppercase letter.')
  .refine((v) => /[0-9]/.test(v), 'Include a number.')

export const signInSchema = z.object({
  email,
  // No policy at sign-in: never reveal or block on the password rules here.
  password: z.string().min(1, 'Enter your password.').max(256),
})

export const signUpSchema = z
  .object({ email, password: newPassword, confirm: z.string() })
  .refine((v) => v.password === v.confirm, {
    path: ['confirm'],
    message: 'Passwords do not match.',
  })

export const forgotSchema = z.object({ email })

export const resetSchema = z
  .object({ password: newPassword, confirm: z.string() })
  .refine((v) => v.password === v.confirm, {
    path: ['confirm'],
    message: 'Passwords do not match.',
  })

export const profileSchema = z.object({
  display_name: z
    .string()
    .trim()
    .min(1, 'Enter a display name.')
    .max(80, 'Use at most 80 characters.'),
  organizational_title: z
    .string()
    .trim()
    .max(100, 'Use at most 100 characters.')
    .transform((v) => (v === '' ? null : v)),
})

export type FieldErrors = Record<string, string>

/** Validate and return either parsed data or a flat map of field -> first message. */
export function validate<S extends z.ZodType>(
  schema: S,
  input: unknown,
): { ok: true; data: z.output<S> } | { ok: false; errors: FieldErrors } {
  const result = schema.safeParse(input)
  if (result.success) return { ok: true, data: result.data }
  const errors: FieldErrors = {}
  for (const issue of result.error.issues) {
    const key = String(issue.path[0] ?? 'form')
    if (!(key in errors)) errors[key] = issue.message
  }
  return { ok: false, errors }
}
