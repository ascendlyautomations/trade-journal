import { getRouteUser } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** @deprecated Use POST .../connections/{connectionId}/accounts/refresh */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  return Response.json(
    { error: "Refresh a specific Tradovate connection by connection ID." },
    { status: 400 }
  )
}
