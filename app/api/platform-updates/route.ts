import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listPublishedPlatformUpdates } from "@/lib/server/platformUpdates/platformUpdateService"
import { platformUpdateDestinationHref } from "@/lib/platformUpdateDestinations"

export const runtime = "nodejs"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const updates = await listPublishedPlatformUpdates(supabaseServiceRole)
    return Response.json({
      updates: updates.map((u) => ({
        id: u.id,
        title: u.title,
        body: u.body,
        category: u.category,
        destination: u.destination,
        href: platformUpdateDestinationHref(u.destination),
        publishedAt: u.published_at,
      })),
    })
  } catch (error) {
    console.error("[api/platform-updates]", error)
    return Response.json({ error: "Failed to load updates" }, { status: 500 })
  }
}
