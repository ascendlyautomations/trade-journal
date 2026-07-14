import { getRouteUser } from "@/app/api/_lib/getRouteUser"

/** Public beta enrollment is closed — codes can no longer grant beta status. */
export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  return Response.json(
    {
      error: "Beta enrollment is closed",
      ok: false,
      applied: false,
      reason: "enrollment_closed",
    },
    { status: 403 }
  )
}
