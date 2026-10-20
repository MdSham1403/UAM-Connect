import { parseOtpType, type OtpFlowType } from './authApi'

/** What the page URL asked us to do when the user arrived from an email link. */
export interface UrlFlow {
  flow: 'confirm' | 'recovery' | null
  tokenHash: string | null
  otpType: OtpFlowType | null
  /** A safe, fixed message when the link carried an error (never the raw server text). */
  errorMessage: string | null
}

const LINK_EXPIRED = 'That link is invalid or has expired. Request a new one.'

export function readUrlFlow(
  loc: Pick<Location, 'search' | 'hash'> = window.location,
): UrlFlow {
  const query = new URLSearchParams(loc.search)
  const hash = new URLSearchParams(
    loc.hash.startsWith('#') ? loc.hash.slice(1) : loc.hash,
  )
  const get = (k: string) => query.get(k) ?? hash.get(k)
  const flowParam = query.get('flow')
  const hasError = get('error') !== null || get('error_code') !== null
  return {
    flow:
      flowParam === 'confirm' || flowParam === 'recovery' ? flowParam : null,
    tokenHash: query.get('token_hash'),
    otpType: parseOtpType(query.get('type')),
    errorMessage: hasError ? LINK_EXPIRED : null,
  }
}

const SENSITIVE_PARAMS = [
  'code',
  'token_hash',
  'type',
  'flow',
  'error',
  'error_code',
  'error_description',
]

/** Remove one-time tokens, codes and flow markers from the address bar and history entry. */
export function cleanUrl(): void {
  const url = new URL(window.location.href)
  let changed = url.hash !== ''
  for (const key of SENSITIVE_PARAMS) {
    if (url.searchParams.has(key)) {
      url.searchParams.delete(key)
      changed = true
    }
  }
  if (changed)
    window.history.replaceState(
      window.history.state,
      '',
      `${url.pathname}${url.search}`,
    )
}

export function redirectFor(flow: 'confirm' | 'recovery'): string {
  return `${window.location.origin}/?flow=${flow}`
}
