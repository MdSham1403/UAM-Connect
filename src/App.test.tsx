import { act, render, screen, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createFakeClient, makeSession } from './test/fakeSupabase'

const setup = vi.hoisted(() => ({ current: null as unknown }))
vi.mock('./lib/supabase', () => ({ getSupabase: () => setup.current }))

import App from './App'

beforeEach(() => {
  setup.current = null
})

describe('App (mocked client)', () => {
  it('shows a configuration error instead of crashing when Supabase is not configured', () => {
    setup.current = { ok: false, message: 'Supabase is not configured.' }
    render(<App />)
    expect(
      screen.getByRole('heading', { name: 'UAM Connect' }),
    ).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Supabase is not configured.',
    )
  })
  it('shows sign-in to an unauthenticated visitor', async () => {
    const fake = createFakeClient()
    setup.current = { ok: true, client: fake.client }
    render(<App />)
    expect(
      await screen.findByRole('heading', { name: 'Sign in' }),
    ).toBeInTheDocument()
    expect(fake.from).not.toHaveBeenCalled()
  })
  it('treats a signed-in user with no membership as a non-member: join form, no team data requested', async () => {
    const fake = createFakeClient({
      session: makeSession('me@example.invalid'),
    })
    setup.current = { ok: true, client: fake.client }
    render(<App />)
    expect(
      await screen.findByRole('heading', { name: 'Join your team' }),
    ).toBeInTheDocument()
    expect(screen.getByText('me@example.invalid')).toBeInTheDocument()
    await waitFor(() => expect(fake.from).toHaveBeenCalled())
    expect(fake.calls.from).not.toContain('teams')
    expect(new Set(fake.calls.from)).toEqual(
      new Set(['team_memberships', 'profiles']),
    )
  })
  it('returns to sign-in after sign-out', async () => {
    const fake = createFakeClient({ session: makeSession() })
    setup.current = { ok: true, client: fake.client }
    render(<App />)
    await screen.findByRole('heading', { name: 'Join your team' })
    act(() => fake.emit('SIGNED_OUT', null))
    expect(
      await screen.findByRole('heading', { name: 'Sign in' }),
    ).toBeInTheDocument()
  })
})
