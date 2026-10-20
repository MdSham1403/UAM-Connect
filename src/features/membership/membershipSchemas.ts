import { z } from 'zod'

// Usability only; redeem_join_code validates again in the database.
export const joinSchema = z.object({
  code: z
    .string()
    .trim()
    .min(10, 'Enter the full joining code.')
    .max(64, 'That code is too long.')
    .refine(
      (v) => /^[A-Za-z0-9\s-]+$/.test(v),
      'Use only letters, numbers and dashes.',
    ),
  display_name: z
    .string()
    .trim()
    .min(1, 'Enter your name.')
    .max(80, 'Use at most 80 characters.'),
  organizational_title: z
    .string()
    .trim()
    .max(100, 'Use at most 100 characters.')
    .transform((v) => (v === '' ? null : v)),
})
