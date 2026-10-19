"use client"

import Link from "next/link"
import { useState } from "react"
import Button from "@/app/components/ui/Button"
import Modal from "@/app/components/ui/Modal"
import type { TraderDailyCheckInDraft } from "@/lib/dailyCheckIn/types"
import {
  formatSleepHoursInput,
  parseSleepHoursInput,
  sanitizeSleepHoursTyping,
} from "@/lib/dailyCheckIn/validation"
import CheckInRatingSelector from "./CheckInRatingSelector"

type DailyCheckInModalProps = {
  open: boolean
  dateKey: string
  draft: TraderDailyCheckInDraft
  onDraftChange: (draft: TraderDailyCheckInDraft) => void
  saving: boolean
  errorMessage: string | null
  onClose: () => void
  onSave: () => void
  /** iOS Daily Check-In toolbar — opens check-in history. */
  historyHref?: string
}

export default function DailyCheckInModal({
  open,
  dateKey,
  draft,
  onDraftChange,
  saving,
  errorMessage,
  onClose,
  onSave,
  historyHref = "/check-in-history",
}: DailyCheckInModalProps) {
  const [sleepHoursText, setSleepHoursText] = useState(() =>
    formatSleepHoursInput(draft.sleepHours)
  )

  function update<K extends keyof TraderDailyCheckInDraft>(
    key: K,
    value: TraderDailyCheckInDraft[K]
  ) {
    onDraftChange({ ...draft, [key]: value })
  }

  function handleSleepHoursChange(raw: string) {
    const next = sanitizeSleepHoursTyping(raw)
    setSleepHoursText(next)
    update("sleepHours", parseSleepHoursInput(next))
  }

  const saveDisabled = saving

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onClose}
      title="Daily Check-In"
      size="md"
      belowNavbar
      closeDisabled={saving}
      panelClassName="max-w-lg"
    >
      <form
        className="space-y-4"
        data-testid="dailyCheckIn.sheet"
        aria-describedby="dailyCheckIn.date"
        onSubmit={(event) => {
          event.preventDefault()
          if (saveDisabled) return
          onSave()
        }}
      >
        {historyHref ? (
          <div className="flex justify-end">
            <Link
              href={historyHref}
              onClick={onClose}
              className="text-sm font-semibold text-accent hover:underline"
              data-testid="dailyCheckIn.history"
            >
              History
            </Link>
          </div>
        ) : null}
        <p id="dailyCheckIn.date" className="sr-only">
          Check-in date {dateKey}
        </p>
        <section className="space-y-3 rounded-xl border border-border bg-surface-secondary/60 p-3.5">
          <h3 className="text-sm font-semibold text-foreground">Sleep</h3>
          <label className="block space-y-1.5">
            <span className="text-sm font-semibold text-foreground">
              Hours of Sleep
            </span>
            <span className="flex items-center gap-2">
              <input
                type="text"
                inputMode="decimal"
                placeholder="7.5"
                value={sleepHoursText}
                disabled={saving}
                onChange={(event) => handleSleepHoursChange(event.target.value)}
                data-testid="dailyCheckIn.sleepHours"
                className="min-h-11 w-24 rounded-lg border border-border bg-surface-elevated px-3 py-2 text-sm text-foreground outline-none placeholder:text-muted-foreground focus:border-accent"
              />
              <span className="text-sm text-muted-foreground">hours</span>
            </span>
          </label>
          <CheckInRatingSelector
            title="Sleep Quality"
            value={draft.sleepQuality}
            onChange={(value) => update("sleepQuality", value)}
            lowLabel="Poor"
            highLabel="Great"
            disabled={saving}
            testId="dailyCheckIn.sleepQuality"
          />
        </section>

        <section className="space-y-3 rounded-xl border border-border bg-surface-secondary/60 p-3.5">
          <h3 className="text-sm font-semibold text-foreground">Morning</h3>
          <CheckInRatingSelector
            title="How's your morning?"
            value={draft.morningRating}
            onChange={(value) => update("morningRating", value)}
            lowLabel="Rough"
            highLabel="Great"
            disabled={saving}
            testId="dailyCheckIn.morning"
          />
        </section>

        <section className="space-y-3 rounded-xl border border-border bg-surface-secondary/60 p-3.5">
          <h3 className="text-sm font-semibold text-foreground">Mental State</h3>
          <CheckInRatingSelector
            title="Stress"
            value={draft.stressLevel}
            onChange={(value) => update("stressLevel", value)}
            lowLabel="Calm"
            highLabel="Very Stressed"
            disabled={saving}
            testId="dailyCheckIn.stress"
          />
          <CheckInRatingSelector
            title="Energy"
            value={draft.energyLevel}
            onChange={(value) => update("energyLevel", value)}
            lowLabel="Low"
            highLabel="High"
            disabled={saving}
            testId="dailyCheckIn.energy"
          />
          <CheckInRatingSelector
            title="Focus"
            value={draft.focusLevel}
            onChange={(value) => update("focusLevel", value)}
            lowLabel="Scattered"
            highLabel="Sharp"
            disabled={saving}
            testId="dailyCheckIn.focus"
          />
        </section>

        <section className="space-y-2 rounded-xl border border-border bg-surface-secondary/60 p-3.5">
          <h3 className="text-sm font-semibold text-foreground">Notes</h3>
          <p className="text-xs text-muted-foreground">
            Anything affecting your trading today?
          </p>
          <textarea
            value={draft.notes}
            disabled={saving}
            onChange={(event) => update("notes", event.target.value)}
            data-testid="dailyCheckIn.notes"
            rows={3}
            className="min-h-[72px] w-full resize-none rounded-lg border border-border bg-surface-elevated px-3 py-2 text-sm text-foreground outline-none placeholder:text-muted-foreground focus:border-accent"
          />
        </section>

        {errorMessage ? (
          <p className="text-sm text-negative" role="alert">
            {errorMessage}
          </p>
        ) : null}

        <Button
          type="submit"
          variant="primary"
          fullWidth
          disabled={saveDisabled}
          data-testid="dailyCheckIn.save"
        >
          {saving ? "Saving…" : "Save Check-In"}
        </Button>
      </form>
    </Modal>
  )
}
