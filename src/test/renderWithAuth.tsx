import { render } from '@testing-library/react'
import type { ReactElement } from 'react'
import { AuthProvider } from '../features/auth/AuthProvider'
import type { createFakeClient } from './fakeSupabase'

export function renderWithAuth(
  ui: ReactElement,
  fake: ReturnType<typeof createFakeClient>,
) {
  return render(<AuthProvider client={fake.client}>{ui}</AuthProvider>)
}
