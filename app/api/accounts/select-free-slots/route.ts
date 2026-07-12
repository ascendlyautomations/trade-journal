import { NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"
import { isProActive } from "@/lib/subscription"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export const runtime = "nodejs"

const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

/**
 * Free-plan downgrade: keep 0–3 accounts entry-enabled; rest read-only.
 * Body: { accountIds: string[] } — length 0..3, owned by the caller.
 */
export async function POST(req: Request) {
  try {
    const cookieStore = await cookies()
    const supabaseAuth = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get: (name) => cookieStore.get(name)?.value,
        },
      }
    )

    const {
      data: { user },
    } = await supabaseAuth.auth.getUser()

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

    if (accountIds.length > FREE_PLAN_ACCOUNT_LIMIT) {
      return NextResponse.json(
        {
          error: `Select at most ${FREE_PLAN_ACCOUNT_LIMIT} accounts.`,
        },
        { status: 400 }
      )
    }

    if (new Set(accountIds).size !== accountIds.length) {
      return NextResponse.json(
        { error: "Selected accounts must be distinct." },
        { status: 400 }
      )
    }

    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("is_pro, subscription_status, trial_end")
      .eq("id", user.id)
      .maybeSingle()

    if (isProActive(profile)) {
      await supabaseAdmin
        .from("accounts")
        .update({ can_add_trades: true })
        .eq("user_id", user.id)
      return NextResponse.json({ ok: true, pro: true })
    }

    if (accountIds.length > 0) {
      const { data: owned, error: ownedErr } = await supabaseAdmin
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

    const { error: disableErr } = await supabaseAdmin
      .from("accounts")
      .update({ can_add_trades: false })
      .eq("user_id", user.id)

    if (disableErr) {
      console.error("[select-free-slots] disable", disableErr)
      return NextResponse.json({ error: "Could not update accounts." }, { status: 500 })
    }

    if (accountIds.length > 0) {
      const { error: enableErr } = await supabaseAdmin
        .from("accounts")
        .update({ can_add_trades: true })
        .eq("user_id", user.id)
        .in("id", accountIds)

      if (enableErr) {
        console.error("[select-free-slots] enable", enableErr)
        return NextResponse.json(
          { error: "Could not update accounts." },
          { status: 500 }
        )
      }
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
