"use client"

import { useMemo } from "react"
import SystemMilestoneCard from "@/app/components/milestones/SystemMilestoneCard"
import {
  resolveSystemMilestones,
  unlockedSystemMilestones,
} from "@/lib/userMilestones"
import type { MilestoneSignals } from "@/lib/userMilestones"

type Props = {
  userId: string | null | undefined
  signals: MilestoneSignals | null | undefined
  loading?: boolean
}

export default function SystemMilestonesSection({
  userId,
  signals,
  loading = false,
}: Props) {
  const milestones = useMemo(() => {
    if (!signals) return []
    return resolveSystemMilestones(userId, signals)
  }, [signals, userId])

  const unlockedCount = useMemo(() => {
    if (!signals) return 0
    return unlockedSystemMilestones(userId, signals).length
  }, [signals, userId])

  return (
    <section className="space-y-4" aria-labelledby="system-milestones-heading">
      <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2
            id="system-milestones-heading"
            className="text-lg font-semibold text-white"
          >
            ⭐ Milestones
          </h2>
          <p className="mt-1 text-sm text-gray-400">
            Permanent unlocks earned across your trading journey.
          </p>
        </div>
        {!loading && signals ? (
          <p className="text-xs text-gray-500">
            {unlockedCount} of {milestones.length} unlocked
          </p>
        ) : null}
      </div>

      {loading ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <div
              key={index}
              className="h-24 animate-pulse rounded-xl border border-white/10 bg-white/5"
            />
          ))}
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {milestones.map((milestone) => (
            <SystemMilestoneCard key={milestone.id} milestone={milestone} />
          ))}
        </div>
      )}
    </section>
  )
}
