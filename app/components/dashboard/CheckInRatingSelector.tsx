"use client"

type CheckInRatingSelectorProps = {
  title: string
  value: number
  onChange: (value: number) => void
  lowLabel: string
  highLabel: string
  disabled?: boolean
  testId?: string
}

export default function CheckInRatingSelector({
  title,
  value,
  onChange,
  lowLabel,
  highLabel,
  disabled = false,
  testId,
}: CheckInRatingSelectorProps) {
  return (
    <div className="space-y-1.5" data-testid={testId}>
      <p className="text-sm font-semibold text-foreground">{title}</p>
      <div className="flex gap-1.5">
        {[1, 2, 3, 4, 5].map((level) => {
          const selected = value === level
          return (
            <button
              key={level}
              type="button"
              disabled={disabled}
              aria-label={`${title} ${level} of 5`}
              aria-pressed={selected}
              onClick={() => onChange(level)}
              className={`min-h-11 flex-1 rounded-lg border px-1 py-2 text-sm font-semibold tabular-nums transition ${
                selected
                  ? "border-accent bg-accent/15 text-accent"
                  : "border-border bg-surface-secondary text-foreground hover:bg-surface-elevated"
              }`}
            >
              {level}
            </button>
          )
        })}
      </div>
      <div className="flex justify-between text-[11px] text-muted-foreground">
        <span>{lowLabel}</span>
        <span>{highLabel}</span>
      </div>
    </div>
  )
}
