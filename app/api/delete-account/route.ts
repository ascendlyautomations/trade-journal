import Stripe from "stripe"
import { NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { deleteUserAccount } from "@/lib/deleteUserAccount"
import {
  AdminUserDeletionError,
  AdminUserDeletionStepError,
} from "@/lib/deleteUserAdmin"

const stripe = process.env.STRIPE_SECRET_KEY
  ? new Stripe(process.env.STRIPE_SECRET_KEY)
  : null

export async function POST(req: Request) {
  const user = await getRouteUser(req)

  if (!user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    await deleteUserAccount(supabaseServiceRole, {
      userId: user.id,
      stripe,
    })
  } catch (err) {
    if (err instanceof AdminUserDeletionError) {
      const status =
        err.code === "NOT_FOUND" ? 404 : err.code === "ADMIN_TARGET" ? 403 : 400
      return NextResponse.json({ error: err.message }, { status })
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
