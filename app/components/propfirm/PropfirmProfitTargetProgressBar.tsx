import { cn } from "@/app/components/ui/cn"

type PropfirmProfitTargetProgressBarProps = {
  /** Fill width 0–100 toward (or below) the profit target. */
  progressPercent: number
  /** When true, fill is solid red; otherwise solid green. */
  negative?: boolean
  className?: string
}

/**
 * Left-origin profit target bar: green when profitable, red when below breakeven.
 */
export default function PropfirmProfitTargetProgressBar({
  progressPercent,
  negative = false,
  className,
}: PropfirmProfitTargetProgressBarProps) {
  const clamped = Math.max(0, Math.min(100, Number(progressPercent) || 0))

  return (
    <div
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(clamped)}
      aria-label="Profit target progress"
      className={cn(
        "h-2 w-full overflow-hidden rounded-full bg-white/10",
        className
      )}
    >
      <div
        className={cn(
          "h-full rounded-full transition-[width] duration-300",
          negative ? "bg-red-500" : "bg-emerald-500"
        )}
        style={{ width: `${clamped}%` }}
      />
    </div>
  )
}
