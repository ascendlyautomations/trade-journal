import type { StreakStats } from "@/lib/userStreaksLogic"

type StreakCardProps = {
  icon: string
  title: string
  description: string
  stats: StreakStats
  loading?: boolean
}

export default function StreakCard({
  icon,
  title,
  description,
  stats,
  loading = false,
}: StreakCardProps) {
  const progressPct = Math.round(stats.progressRatio * 100)
  const nextLabel =
    stats.nextMilestone != null
      ? `${stats.current} / ${stats.nextMilestone}`
      : `${stats.current}`

  return (
    <article className="flex h-full flex-col rounded-xl border border-white/10 bg-white/[0.06] p-5 shadow-lg shadow-black/20 md:p-6">
      <div className="mb-5">
        <h3 className="text-lg font-semibold text-white">
          {icon} {title}
        </h3>
        <p className="mt-2 text-sm leading-relaxed text-gray-400">{description}</p>
      </div>

      {loading ? (
        <div className="flex flex-1 flex-col gap-4 animate-pulse">
          <div className="h-16 rounded-lg bg-white/10" />
          <div className="h-3 rounded-full bg-white/10" />
        </div>
      ) : (
        <div className="mt-auto space-y-5">
          <div className="grid grid-cols-3 gap-3 text-center sm:gap-4">
            <div>
              <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
                Current
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-white">
                {stats.current}
              </p>
              <p className="text-xs text-gray-400">{stats.unitLabel}</p>
            </div>
            <div>
              <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
                Longest
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-300">
                {stats.longest}
              </p>
              <p className="text-xs text-gray-400">{stats.unitLabel}</p>
            </div>
            <div>
              <p className="text-[11px] font-medium uppercase tracking-wide text-gray-400">
                Next Goal
              </p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-blue-300">
                {stats.nextMilestone ?? "—"}
              </p>
              <p className="text-xs text-gray-400">
                {stats.nextMilestone != null ? stats.unitLabel : "Maxed"}
              </p>
            </div>
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between text-xs text-gray-400">
              <span>Progress</span>
              <span className="font-medium tabular-nums text-gray-300">{nextLabel}</span>
            </div>
            <div className="h-2.5 overflow-hidden rounded-full bg-white/10">
              <div
                className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 transition-[width] duration-500"
                style={{ width: `${progressPct}%` }}
              />
            </div>
          </div>
        </div>
      )}
    </article>
  )
}
