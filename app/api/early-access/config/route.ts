import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { resolveEarlyAccessEnvironment } from "@/lib/earlyAccessEnvironment.server"
import { EARLY_ACCESS_CAMPAIGN_KEY } from "@/lib/earlyAccess"

export const dynamic = "force-dynamic"

export async function GET() {
  const { data, error } = await supabaseServiceRole
    .from("early_access_campaigns")
    .select("enrollment_enabled, award_limit")
    .eq("campaign_key", EARLY_ACCESS_CAMPAIGN_KEY)
    .eq("environment", resolveEarlyAccessEnvironment())
    .maybeSingle()

  if (error) {
    console.error("[early-access/config]", error)
    return Response.json(
      { enabled: false, awardLimit: 0 },
      { headers: { "Cache-Control": "no-store" } }
    )
  }

  return Response.json(
    {
      enabled: data?.enrollment_enabled === true,
      awardLimit: Number(data?.award_limit ?? 0),
    },
    { headers: { "Cache-Control": "no-store" } }
  )
}
