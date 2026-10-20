"use client"

import ExpandableText from "@/app/components/ui/ExpandableText"

type BacktestLabReflectionPreviewProps = {
  trade: Record<string, unknown>
}

function line(label: string, value: string | null | undefined) {
  if (!value?.trim()) return null
  return (
    <p className="text-xs text-gray-300 md:text-sm">
      <span className="text-gray-400">{label}:</span> {value}
    </p>
  )
}

export default function BacktestLabReflectionPreview({
  trade,
}: BacktestLabReflectionPreviewProps) {
  const confluences =
    String(trade.top_confluences ?? trade.notes ?? "").trim() || null
  const psychology = String(trade.psychology_notes ?? "").trim() || null
  const entryReasoning = String(trade.public_description ?? "").trim() || null
  const followed =
    trade.followed_plan === true
      ? "Yes"
      : trade.followed_plan === false
        ? "No"
        : null
  const mistake = String(trade.mistake_type ?? "").trim() || null

  const hasContent =
    confluences || psychology || entryReasoning || followed || mistake

  if (!hasContent) {
    return (
      <p className="text-xs text-gray-500">
        No reflection notes yet — edit trade to add confluences, psychology notes,
        plan follow-through, and lessons.
      </p>
    )
  }

  return (
    <div className="space-y-1 rounded-lg border border-white/10 bg-black/20 p-2.5">
      <p className="text-[10px] font-semibold uppercase tracking-wide text-blue-300/90">
        Journal snapshot
      </p>
      {line("Entry / public notes", entryReasoning)}
      {confluences ? (
        <ExpandableText
          className="min-w-0 text-xs text-gray-300"
          label="Confluences:"
          stopPropagation
        >
          {confluences}
        </ExpandableText>
      ) : null}
      {psychology ? (
        <ExpandableText
          className="min-w-0 text-xs text-gray-300"
          label="Psychology / lessons:"
          stopPropagation
        >
          {psychology}
        </ExpandableText>
      ) : null}
      {line("Followed plan", followed)}
      {line("Mistake type", mistake)}
    </div>
  )
}
