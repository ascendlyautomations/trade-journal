import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { declineFollowRequest } from "../_lib/respondToFollowRequest"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let requestId: string | undefined
  try {
    const body = (await req.json()) as { requestId?: string }
    requestId = body.requestId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!requestId) {
    return Response.json({ error: "Invalid requestId" }, { status: 400 })
  }

  const result = await declineFollowRequest(user, requestId)
  if (!result.ok) {
    return Response.json({ error: result.error }, { status: result.status })
  }

  return Response.json({ ok: true })
}
