import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveEarlyAccessEnvironment } from "@/lib/earlyAccessEnvironment.server"

export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const environment = resolveEarlyAccessEnvironment()

  const { error: expireError } = await supabaseServiceRole.rpc(
    "expire_early_access",
    { p_user_id: user.id }
  )
  if (expireError) {
    console.error("[early-access/status] expiration:", expireError)
    return Response.json(
      { error: "Could not refresh Early Access status." },
      { status: 500 }
    )
  }

  const { data, error } = await supabaseServiceRole.rpc(
    "get_early_access_progress",
    {
      p_user_id: user.id,
      p_environment: environment,
    }
  )

  if (error) {
    console.error("[early-access/status] progress:", error)
    return Response.json(
      { error: "Could not load Early Access progress." },
      { status: 500 }
    )
  }

  const row = Array.isArray(data) ? data[0] : data
  if (!row) {
    return Response.json({ progress: null })
  }

  return Response.json({
    progress: {
      status: row.status ?? null,
      enrolledAt: row.enrolled_at ?? null,
      endsAt: row.ends_at ?? null,
      followCount: Number(row.follow_count ?? 0),
      publicTradeDayCount: Number(row.public_trade_day_count ?? 0),
      referralCount: Number(row.referral_count ?? 0),
      completedCount: Number(row.completed_count ?? 0),
      allComplete: row.all_complete === true,
      awardLimit: Number(row.award_limit ?? 0),
      awardsClaimed: Number(row.awards_claimed ?? 0),
      spotsRemaining: Number(row.spots_remaining ?? 0),
      alreadyAwarded: row.already_awarded === true,
    },
  })
}
