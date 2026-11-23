import type { FunnelStage } from "@/lib/adminLifecycleAnalytics"
import { funnelStageConversionLabel } from "@/lib/adminLifecycleAnalytics"

export function FunnelStagesTable({ stages }: { stages: FunnelStage[] }) {
  if (!stages.length) {
    return <p className="text-sm text-gray-400">No funnel data.</p>
  }
  return (
    <div className="overflow-x-auto rounded-xl border border-white/10 bg-black/20">
      <table className="min-w-full text-left text-sm">
        <thead className="text-xs uppercase text-gray-400">
          <tr>
            <th className="px-3 py-2">Stage</th>
            <th className="px-3 py-2">Users</th>
            <th className="px-3 py-2">From signup</th>
            <th className="px-3 py-2">Drop-off</th>
          </tr>
        </thead>
        <tbody>
          {stages.map((stage) => (
            <tr key={stage.id} className="border-t border-white/5 text-gray-200">
              <td className="px-3 py-2 font-medium">
                {stage.label}
                {stage.awaitingData ? (
                  <span className="ml-2 text-xs text-amber-200/90">(awaiting data)</span>
                ) : null}
              </td>
              <td className="px-3 py-2 tabular-nums">{stage.count.toLocaleString()}</td>
              <td className="px-3 py-2 tabular-nums">{funnelStageConversionLabel(stage)}</td>
              <td className="px-3 py-2 tabular-nums">
                {stage.dropOffFromPriorPct != null ? `${stage.dropOffFromPriorPct}%` : "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}