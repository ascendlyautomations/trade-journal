"use client"

type MobileWebDashboardWinLossProps = {
  winRate: number
  winCount: number
  lossCount: number
}

export default function MobileWebDashboardWinLoss({
  winRate,
  winCount,
  lossCount,
}: MobileWebDashboardWinLossProps) {
  const radius = 46
  const circumference = 2 * Math.PI * radius
  const clamped = Math.max(0, Math.min(100, winRate))
  const winArc = (clamped / 100) * circumference

  return (
    <div className="flex items-center gap-4">
      <div className="relative h-[120px] w-[120px] shrink-0">
        <svg viewBox="0 0 120 120" className="h-full w-full -rotate-90">
          <circle
            cx="60"
            cy="60"
            r={radius}
            fill="none"
            stroke="rgb(255 255 255 / 0.12)"
            strokeWidth="10"
          />
          <circle
            cx="60"
            cy="60"
            r={radius}
            fill="none"
            stroke="#34d399"
            strokeWidth="10"
            strokeLinecap="butt"
            strokeDasharray={`${winArc} ${circumference}`}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-[20px] font-semibold tabular-nums text-[color:var(--tt-text,#f0f3f6)]">
            {winRate.toFixed(0)}%
          </span>
          <span className="text-[10px] uppercase tracking-wide text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            Win rate
          </span>
        </div>
      </div>
      <div className="min-w-0 flex-1 space-y-2">
        <p className="flex items-center justify-between text-[15px]">
          <span className="text-[color:var(--tt-text-muted,#c0cad6)]">Wins</span>
          <span className="font-semibold tabular-nums text-emerald-400">
            {winCount}
          </span>
        </p>
        <p className="flex items-center justify-between text-[15px]">
          <span className="text-[color:var(--tt-text-muted,#c0cad6)]">Losses</span>
          <span className="font-semibold tabular-nums text-red-400">
            {lossCount}
          </span>
        </p>
      </div>
    </div>
  )
}
