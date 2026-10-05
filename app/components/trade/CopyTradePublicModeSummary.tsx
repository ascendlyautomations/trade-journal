"use client"

type CopyTradePublicModeSummaryProps = {
  summary: string | null | undefined
  className?: string
}

/** Feed/profile: `Copy Traded on 1 Live • 2 Funded` under direction line. */
export default function CopyTradePublicModeSummary({
  summary,
  className = "",
}: CopyTradePublicModeSummaryProps) {
  const text = summary?.trim()
  if (!text) return null
  return (
    <p
      className={`text-xs font-medium text-violet-200/90 md:text-sm ${className}`}
      data-testid="copy-trade-public-mode-summary"
    >
      {text}
    </p>
  )
}
