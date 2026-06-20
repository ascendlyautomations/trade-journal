export type DashboardSessionBucket = "NY" | "Asia" | "London"

export const DASHBOARD_SESSION_DISPLAY_ORDER: readonly DashboardSessionBucket[] =
  ["NY", "Asia", "London"] as const

export const DASHBOARD_SESSION_COLORS: Record<DashboardSessionBucket, string> =
  {
    NY: "#34d399",
    Asia: "#c084fc",
    London: "#60a5fa",
  }

/** Map user/session CSV labels to dashboard session buckets. */
export function normalizeSessionBucket(
  sessionRaw: string | null | undefined
): DashboardSessionBucket | null {
  const s = (sessionRaw || "").trim().toLowerCase()
  if (!s) return null
  if (s === "london") return "London"
  if (s === "asia") return "Asia"
  if (
    s === "ny" ||
    s === "new york" ||
    s === "ny am" ||
    s === "am" ||
    s === "after"
  ) {
    return "NY"
  }
  return null
}
