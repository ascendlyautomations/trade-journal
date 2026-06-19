import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { fetchAdminUserDeletionPreview } from "@/lib/adminUserDeletionPreview"
import { requireAdminApiUser } from "@/lib/requireAdminApi"

export const runtime = "nodejs"

type RouteContext = { params: Promise<{ userId: string }> }

export async function GET(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { userId } = await context.params
  const targetUserId = userId?.trim()
  if (!targetUserId) {
    return Response.json({ error: "Missing user id" }, { status: 400 })
  }

  const { preview, error } = await fetchAdminUserDeletionPreview(
    supabaseServiceRole,
    targetUserId
  )

  if (error || !preview) {
    return Response.json({ error: error ?? "User not found" }, { status: 404 })
  }

  return Response.json({ preview })
}
