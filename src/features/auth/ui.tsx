import type { InputHTMLAttributes, ReactNode } from 'react'

export function Field({
  label,
  name,
  error,
  ...input
}: {
  label: string
  name: string
  error?: string
} & InputHTMLAttributes<HTMLInputElement>) {
  const errorId = `${name}-error`
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={name} className="text-sm font-medium">
        {label}
      </label>
      <input
        id={name}
        name={name}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : undefined}
        className="min-h-11 rounded-md border border-gray-300 px-3 py-2 text-base"
        {...input}
      />
      {error ? (
        <p id={errorId} className="text-sm text-red-700">
          {error}
        </p>
      ) : null}
    </div>
  )
}

export function Banner({
  kind,
  children,
}: {
  kind: 'error' | 'info'
  children: ReactNode
}) {
  const tone =
    kind === 'error'
      ? 'border-red-300 bg-red-50 text-red-800'
      : 'border-blue-300 bg-blue-50 text-blue-900'
  return (
    <p
      role={kind === 'error' ? 'alert' : 'status'}
      className={`rounded-md border px-3 py-2 text-sm ${tone}`}
    >
      {children}
    </p>
  )
}

export function PrimaryButton({
  children,
  pending,
  ...rest
}: { pending?: boolean } & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      type="submit"
      disabled={pending || rest.disabled}
      className="min-h-11 rounded-md bg-gray-900 px-4 py-2 text-base font-medium text-white disabled:opacity-60"
      {...rest}
    >
      {pending ? 'Please wait…' : children}
    </button>
  )
}

export function LinkButton({
  children,
  ...rest
}: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type="button" className="min-h-11 text-sm underline" {...rest}>
      {children}
    </button>
  )
}
