"use client"

/** Tiny inline spinner — never replaces button label / layout. */
export default function InlineMicroSpinner({
  className = "",
  label = "Working",
}: {
  className?: string
  label?: string
}) {
  return (
    <span
      className={`tt-micro-spinner inline-block shrink-0 rounded-full border-2 border-current border-t-transparent ${className}`.trim()}
      role="status"
      aria-label={label}
    />
  )
}
