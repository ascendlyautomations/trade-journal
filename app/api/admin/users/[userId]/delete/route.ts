import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  AdminUserDeletionError,
  deleteUserAdmin,
} from "@/lib/deleteUserAdmin"
import { requireAdminApiUser } from "@/lib/requireAdminApi"
import { getStripeServer } from "@/lib/stripeServer"

export const runtime = "nodejs"

type RouteContext = { params: Promise<{ userId: string }> }

export async function POST(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { userId } = await context.params
  const targetUserId = userId?.trim()
  if (!targetUserId) {
    return Response.json({ error: "Missing user id" }, { status: 400 })
  }

  let body: { confirmation?: string }
  try {
    body = (await req.json()) as { confirmation?: string }
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 })
  }

  if (body.confirmation !== "DELETE") {
    return Response.json(
      { error: 'Type DELETE to confirm permanent deletion.' },
      { status: 400 }
    )
  }

  try {
    const stripe = process.env.STRIPE_SECRET_KEY ? getStripeServer() : null
    const result = await deleteUserAdmin(supabaseServiceRole, {
      adminUserId: auth.adminUser.id,
      targetUserId,
      stripe,
    })

    return Response.json({ success: true, ...result })
  } catch (err) {
    if (err instanceof AdminUserDeletionError) {
      const status =
        err.code === "NOT_FOUND"
          ? 404
          : err.code === "SELF_DELETE" || err.code === "ADMIN_TARGET"
            ? 403
            : 500
      return Response.json({ error: err.message, code: err.code }, { status })
    }

    const message = err instanceof Error ? err.message : "Delete failed"
    console.error("[admin/users/delete]", err)
    return Response.json({ error: message }, { status: 500 })
  }
}
