import { getRouteUser } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** @deprecated Use POST .../connections/{connectionId}/accounts/link */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  return Response.json(
    { error: "Link accounts through a specific Tradovate connection ID." },
    { status: 400 }
  )
}
