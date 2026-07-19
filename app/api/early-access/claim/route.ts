import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveEarlyAccessEnvironment } from "@/lib/earlyAccessEnvironment.server"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data, error } = await supabaseServiceRole.rpc(
    "claim_pro_for_life",
    {
      p_user_id: user.id,
      p_environment: resolveEarlyAccessEnvironment(),
    }
  )

  if (error) {
    console.error("[early-access/claim]", error)
    return Response.json(
      { error: "Could not verify the Pro For Life claim." },
      { status: 500 }
    )
  }

  const row = Array.isArray(data) ? data[0] : data
  if (!row?.result) {
    return Response.json(
      { error: "No claim result was returned." },
      { status: 500 }
    )
  }

  return Response.json({
    result: String(row.result),
    awardedAt: row.awarded_at ?? null,
    followCount: Number(row.follow_count ?? 0),
    publicTradeDayCount: Number(row.public_trade_day_count ?? 0),
    referralCount: Number(row.referral_count ?? 0),
    spotsRemaining: Number(row.spots_remaining ?? 0),
  })
}
