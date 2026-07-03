import type { ResolvedSystemMilestone } from "@/lib/userMilestones"

type SystemMilestoneCardProps = {
  milestone: ResolvedSystemMilestone
}

export default function SystemMilestoneCard({ milestone }: SystemMilestoneCardProps) {
  return (
    <article
      className={`rounded-xl border p-4 shadow-lg shadow-black/15 ${
        milestone.unlocked
          ? "border-emerald-400/30 bg-emerald-500/10"
          : "border-white/10 bg-white/[0.04] opacity-80"
      }`}
    >
      <div className="flex items-start gap-3">
        <span className="text-2xl" aria-hidden>
          {milestone.icon}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <h3 className="font-semibold text-white">{milestone.title}</h3>
            {milestone.unlocked ? (
              <span className="shrink-0 rounded-full border border-emerald-400/30 bg-emerald-500/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-emerald-200">
                Unlocked
              </span>
            ) : null}
          </div>
          <p className="mt-1 text-sm leading-relaxed text-gray-400">
            {milestone.description}
          </p>
        </div>
      </div>
    </article>
  )
}
