import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"
import type { Database } from "@/lib/database.types"
import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { proLimitResponseFromError } from "@/lib/server/proLimitFromError"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"

export const runtime = "nodejs"

/**
 * Applies Free-plan trade-entry slot selection via `select_free_plan_trade_accounts`.
 * Pro callers re-enable all accounts server-side.
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

    if (accountIds.length > FREE_PLAN_ACCOUNT_LIMIT) {
      return NextResponse.json(
        {
          error: `Choose at most ${FREE_PLAN_ACCOUNT_LIMIT} accounts for new trades.`,
        },
        { status: 400 }
      )
    }

    const authHeader = req.headers.get("authorization") || ""
    const bearer = authHeader.startsWith("Bearer ")
      ? authHeader.slice("Bearer ".length).trim()
      : ""

    const supabase = createClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: bearer ? { headers: { Authorization: `Bearer ${bearer}` } } : {},
      }
    )

    const { error: rpcErr } = await supabase.rpc("select_free_plan_trade_accounts", {
      p_account_ids: accountIds,
    })

    if (rpcErr) {
      console.error("[select-free-slots] rpc", rpcErr)
      const proLimit = proLimitResponseFromError(rpcErr, 403)
      if (proLimit) return proLimit
      return NextResponse.json(
        {
          error: toUserFacingErrorMessage(
            rpcErr,
            "Could not save account selection."
          ),
        },
        { status: 400 }
      )
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
