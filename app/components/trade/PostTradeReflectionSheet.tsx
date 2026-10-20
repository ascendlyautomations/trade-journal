"use client"

import { useMemo, useState } from "react"
import CustomSelect from "@/app/components/CustomSelect"
import CheckInRatingSelector from "@/app/components/dashboard/CheckInRatingSelector"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { SELECT_TRIGGER_COMPACT_CLASS } from "@/lib/accountDropdownStyles"
import {
  POST_TRADE_EXIT_EMOTIONS,
  savePostTradeReflection,
} from "@/lib/postTradeReflection"

export type PostTradeReflectionSheetProps = {
  open: boolean
  tradeId: string
  onSkip: () => void
  onComplete: () => void
}

/** Optional quick reflection after creating a trade (native iOS parity). */
export default function PostTradeReflectionSheet({
  open,
  tradeId,
  onSkip,
  onComplete,
}: PostTradeReflectionSheetProps) {
  const { user } = useUserProfile()
  const [exitEmotion, setExitEmotion] = useState("")
  const [executionRating, setExecutionRating] = useState(0)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const emotionOptions = useMemo(
    () => [
      { label: "None", value: "" },
      ...POST_TRADE_EXIT_EMOTIONS.map((label) => ({ label, value: label })),
    ],
    []
  )

  if (!open) return null

  async function handleSave() {
    const trimmedEmotion = exitEmotion.trim()
    const rating = executionRating > 0 ? executionRating : 0
    if (!trimmedEmotion && rating <= 0) {
      onSkip()
      return
    }
    if (!user?.id) return

    setSaving(true)
    setError(null)
    try {
      await savePostTradeReflection(supabase, tradeId, user.id, {
        exitEmotion: trimmedEmotion,
        executionRating: rating,
      })
      onComplete()
    } catch {
      setError("Reflection didn't save. Your trade was still recorded.")
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      className="fixed inset-0 z-[10060] flex items-end justify-center bg-black/60 p-4 sm:items-center"
      role="dialog"
      aria-labelledby="post-trade-reflection-title"
      aria-modal="true"
    >
      <div className="w-full max-w-md rounded-xl border border-border bg-surface-elevated p-5 shadow-xl">
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2
              id="post-trade-reflection-title"
              className="text-lg font-semibold text-foreground"
            >
              Quick Reflection
            </h2>
            <p className="mt-1 text-xs text-muted-foreground">
              Optional — emotion after the trade and execution rating.
            </p>
          </div>
          <button
            type="button"
            disabled={saving}
            onClick={onSkip}
            className="shrink-0 rounded-lg px-3 py-1.5 text-sm font-medium text-muted-foreground transition hover:bg-surface-hover hover:text-foreground disabled:opacity-50"
          >
            Skip
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <p className="mb-1.5 text-xs font-medium text-muted-foreground">
              Emotion after trade
            </p>
            <CustomSelect
              value={exitEmotion}
              onChange={setExitEmotion}
              options={emotionOptions}
              triggerClassName={SELECT_TRIGGER_COMPACT_CLASS}
              aria-label="Emotion after trade"
            />
          </div>

          <CheckInRatingSelector
            title="Execution / discipline"
            value={executionRating}
            onChange={setExecutionRating}
            lowLabel="Needs work"
            highLabel="Strong"
            disabled={saving}
          />

          {error ? (
            <p className="text-xs text-negative" role="alert">
              {error}
            </p>
          ) : null}

          <button
            type="button"
            disabled={saving}
            onClick={() => void handleSave()}
            className="w-full rounded-lg bg-accent py-2.5 text-sm font-semibold text-accent-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {saving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  )
}
