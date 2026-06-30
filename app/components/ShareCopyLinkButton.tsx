"use client"

import { useCallback, useEffect, useRef, useState } from "react"

const COPIED_RESET_MS = 2000

type ShareCopyLinkButtonProps = {
  /** Perform the copy; return true when the clipboard write succeeded. */
  onCopy: () => Promise<boolean>
  onCopyError?: () => void
  className?: string
  /** Idle-state appearance before/after success (success styling is fixed). */
  idleClassName?: string
  disabled?: boolean
}

export default function ShareCopyLinkButton({
  onCopy,
  onCopyError,
  className = "",
  idleClassName = "border-white/10 bg-white/5 text-gray-200 hover:bg-white/10",
  disabled = false,
}: ShareCopyLinkButtonProps) {
  const [copied, setCopied] = useState(false)
  const resetTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const clearResetTimeout = useCallback(() => {
    if (resetTimeoutRef.current != null) {
      clearTimeout(resetTimeoutRef.current)
      resetTimeoutRef.current = null
    }
  }, [])

  useEffect(() => () => clearResetTimeout(), [clearResetTimeout])

  const handleClick = useCallback(async () => {
    if (copied || disabled) return

    const ok = await onCopy()
    if (!ok) {
      onCopyError?.()
      return
    }

    setCopied(true)
    clearResetTimeout()
    resetTimeoutRef.current = setTimeout(() => {
      setCopied(false)
      resetTimeoutRef.current = null
    }, COPIED_RESET_MS)
  }, [clearResetTimeout, copied, disabled, onCopy, onCopyError])

  const stateClass = copied
    ? "cursor-not-allowed border-emerald-500/40 bg-emerald-500/15 text-emerald-300"
    : `border ${idleClassName} disabled:cursor-not-allowed disabled:opacity-40`

  return (
    <button
      type="button"
      onClick={() => void handleClick()}
      disabled={disabled || copied}
      className={`w-full rounded-lg py-2 text-sm font-medium transition ${stateClass} ${className}`.trim()}
    >
      {copied ? "✓ Copied!" : "🔗 Copy Link"}
    </button>
  )
}
