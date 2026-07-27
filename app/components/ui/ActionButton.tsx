"use client"

import type { ButtonHTMLAttributes, ReactNode } from "react"
import InlineMicroSpinner from "@/app/components/ui/InlineMicroSpinner"

type ActionButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  /** When true, keep label and show a tiny inline spinner. */
  syncing?: boolean
  syncingLabel?: string
  children: ReactNode
}

/**
 * Primary/secondary actions that stay readable while syncing.
 * Avoids replacing the whole button with a giant spinner.
 */
export default function ActionButton({
  syncing = false,
  syncingLabel,
  children,
  className = "",
  disabled,
  ...rest
}: ActionButtonProps) {
  return (
    <button
      type="button"
      {...rest}
      disabled={disabled || syncing}
      className={`inline-flex items-center justify-center gap-1.5 ${className}`.trim()}
    >
      <span className={syncing ? "opacity-90" : undefined}>
        {syncing && syncingLabel ? syncingLabel : children}
      </span>
      {syncing ? (
        <InlineMicroSpinner className="h-3.5 w-3.5" label="Working" />
      ) : null}
    </button>
  )
}
