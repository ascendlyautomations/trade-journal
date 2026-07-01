export type ReferredSubscriberStatus = "trial" | "active" | "cancelled"

export function classifyReferredSubscriberStatus(
  subscriptionStatus: string | null | undefined
): ReferredSubscriberStatus {
  const s = String(subscriptionStatus ?? "").toLowerCase().trim()
  if (s === "trialing") return "trial"
  if (s === "active") return "active"
  return "cancelled"
}

/** Sort group: trial → active → cancelled */
export function referredSubscriberStatusOrder(
  status: ReferredSubscriberStatus
): number {
  switch (status) {
    case "trial":
      return 0
    case "active":
      return 1
    case "cancelled":
      return 2
  }
}

export function referredSubscriberStatusLabel(
  status: ReferredSubscriberStatus
): string {
  switch (status) {
    case "trial":
      return "Trial"
    case "active":
      return "Active"
    case "cancelled":
      return "Cancelled"
  }
}

export function referredSubscriberStatusBadgeClass(
  status: ReferredSubscriberStatus
): string {
  switch (status) {
    case "trial":
      return "border-amber-500/40 bg-amber-500/15 text-amber-100"
    case "active":
      return "border-emerald-500/40 bg-emerald-500/15 text-emerald-100"
    case "cancelled":
      return "border-red-500/40 bg-red-500/15 text-red-100"
  }
}

export function formatAffiliateReferralJoinDate(
  raw: string | null | undefined
): string {
  if (!raw) return "—"
  const d = new Date(raw)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

export function sumCommissionByReferredUser(
  rows: Array<{ referred_user_id?: string | null; amount_earned?: unknown }> | null | undefined
): Map<string, number> {
  const map = new Map<string, number>()
  for (const row of rows ?? []) {
    const id = row.referred_user_id != null ? String(row.referred_user_id) : ""
    if (!id) continue
    const n = Number(row.amount_earned)
    if (!Number.isFinite(n)) continue
    map.set(id, Math.round(((map.get(id) ?? 0) + n) * 100) / 100)
  }
  return map
}
