import Stripe from "stripe"
import { NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  AdminUserDeletionError,
  AdminUserDeletionStepError,
  deleteUserAdmin,
} from "@/lib/deleteUserAdmin"
import { getStripeServer } from "@/lib/stripeServer"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

/**
 * Settings → Delete Account.
 * Uses the same deleteUserAdmin() pipeline as Admin Delete User.
 * Only difference: selfService=true (authorization + skip admin audit log).
 */
function resolveStripeForAccountDelete(): Stripe | null {
  if (!process.env.STRIPE_SECRET_KEY) return null
  try {
    return getStripeServer()
  } catch (err) {
    console.warn(
      "[api/delete-account] Stripe client unavailable; continuing without Stripe cleanup:",
      err instanceof Error ? err.message : err
    )
    return null
  }
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)

  if (!user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    await deleteUserAdmin(supabaseServiceRole, {
      adminUserId: user.id,
      targetUserId: user.id,
      stripe: resolveStripeForAccountDelete(),
      selfService: true,
    })
  } catch (err) {
    if (err instanceof AdminUserDeletionError) {
      const status =
        err.code === "NOT_FOUND" ? 404 : err.code === "ADMIN_TARGET" ? 403 : 400
      return NextResponse.json(
        { error: toUserFacingErrorMessage(err) },
        { status }
      )
    }
    if (err instanceof AdminUserDeletionStepError) {
      console.error("[api/delete-account]", err.step, err.table, err.message)
      return NextResponse.json(
        { error: "Account deletion failed. Please contact support." },
        { status: 500 }
      )
    }
    console.error("[api/delete-account]", err)
    return NextResponse.json(
      { error: "Account deletion failed. Please contact support." },
      { status: 500 }
    )
  }

  return NextResponse.json({ success: true })
}
