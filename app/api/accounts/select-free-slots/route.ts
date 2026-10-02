import { NextResponse } from "next/server"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { proLimitResponseFromError } from "@/lib/server/proLimitFromError"

export const runtime = "nodejs"

/**
 * Compatibility endpoint. Previously marked unselected accounts read-only.
 * It now confirms ownership of any ids in the body and enables trade entry
 * on every account the caller owns. Creating accounts is still capped separately.
 */
export async function POST(req: Request) {
  try {
    const user = await getRouteUser(req)

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    let accountIds: string[] = []
    try {
      const body = await req.json()
      const raw = body?.accountIds ?? body?.account_ids
      if (Array.isArray(raw)) {
        accountIds = raw.map((id) => String(id).trim()).filter(Boolean)
      }
    } catch {
      return NextResponse.json({ error: "Invalid request body" }, { status: 400 })
    }

    if (new Set(accountIds).size !== accountIds.length) {
      return NextResponse.json(
        { error: "Selected accounts must be distinct." },
        { status: 400 }
      )
    }

    if (accountIds.length > 0) {
      const { data: owned, error: ownedErr } = await supabaseServiceRole
        .from("accounts")
        .select("id")
        .eq("user_id", user.id)
        .in("id", accountIds)

      if (ownedErr) {
        console.error("[select-free-slots] ownership lookup", ownedErr)
        return NextResponse.json(
          { error: "Could not verify accounts." },
          { status: 500 }
        )
      }

      if ((owned ?? []).length !== accountIds.length) {
        return NextResponse.json(
          { error: "All selected accounts must belong to you." },
          { status: 400 }
        )
      }
    }

    const { error: enableErr } = await supabaseServiceRole
      .from("accounts")
      .update({ can_add_trades: true })
      .eq("user_id", user.id)

    if (enableErr) {
      console.error("[select-free-slots] enable", enableErr)
      const proLimit = proLimitResponseFromError(enableErr, 403)
      if (proLimit) return proLimit
      return NextResponse.json({ error: "Could not update accounts." }, { status: 500 })
    }

    return NextResponse.json({ ok: true })
  } catch (err) {
    console.error("[select-free-slots]", err)
    return NextResponse.json(
      { error: toUserFacingErrorMessage(err, "Could not save account selection.") },
      { status: 500 }
    )
  }
}
