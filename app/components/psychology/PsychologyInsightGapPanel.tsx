"use client"

type PsychologyInsightGapPanelProps = {
  title?: string
  messages: string[]
  testId?: string
}

export default function PsychologyInsightGapPanel({
  title = "What to log next",
  messages,
  testId = "psychologyAnalytics.insightGaps",
}: PsychologyInsightGapPanelProps) {
  if (messages.length === 0) return null

  return (
    <section
      className="rounded-xl border border-white/10 bg-white/5 p-4 max-md:p-3"
      data-testid={testId}
    >
      <h2 className="text-sm font-semibold text-white">{title}</h2>
      <p className="mt-1 text-xs text-gray-400">
        Your analytics overview is unlocked. Comparison cards appear when groups have
        enough matched, tagged trades.
      </p>
      <ul className="mt-3 list-disc space-y-1.5 pl-4 text-xs text-gray-300">
        {messages.map((message) => (
          <li key={message}>{message}</li>
        ))}
      </ul>
    </section>
  )
}
