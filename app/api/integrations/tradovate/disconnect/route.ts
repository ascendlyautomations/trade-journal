import { getRouteUser } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** @deprecated Use POST /api/integrations/tradovate/connections/{connectionId}/disconnect */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  return Response.json(
    {
      error:
        "Specify a Tradovate connection to disconnect. Use Settings → Trading Accounts → Broker integrations.",
    },
    { status: 400 }
  )
}
