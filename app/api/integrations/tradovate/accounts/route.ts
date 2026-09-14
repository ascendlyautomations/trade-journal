import { getRouteUser } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** @deprecated Use GET /api/integrations/tradovate/connections/{connectionId}/accounts */
export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  return Response.json(
    {
      error:
        "Tradovate accounts are connection-scoped. Use GET /api/integrations/tradovate/connections first.",
    },
    { status: 400 }
  )
}
