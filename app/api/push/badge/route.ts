import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import {
  getAppIconBadge,
  invalidateAppIconBadgeCache,
} from "@/lib/server/push/badgeService"

/**
 * Canonical app-icon badge for the authenticated user.
 * Native mirrors this value — it must not derive badge totals locally.
 */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  // Always serve a fresh value for explicit client refreshes.
  invalidateAppIconBadgeCache(user.id)
  const badge = await getAppIconBadge(user.id)
  return Response.json({ badge })
}
