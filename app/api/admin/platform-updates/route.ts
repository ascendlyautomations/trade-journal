import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAdminApiUser } from "@/lib/requireAdminApi"
import {
  isPlatformUpdateCategoryId,
  isPlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import {
  listAdminPlatformUpdates,
  serializeAdminPlatformUpdate,
  validatePlatformUpdateInput,
  type PlatformUpdateRecord,
} from "@/lib/server/platformUpdates/platformUpdateService"

export const runtime = "nodejs"

function serializeAdminUpdate(
  row: Awaited<ReturnType<typeof listAdminPlatformUpdates>>[number]
) {
  return serializeAdminPlatformUpdate(row, row.broadcast)
}

export async function GET(req: Request) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  try {
    const updates = await listAdminPlatformUpdates(supabaseServiceRole)
    return Response.json({ updates: updates.map(serializeAdminUpdate) })
  } catch (error) {
    console.error("[api/admin/platform-updates]", error)
    return Response.json({ error: "Failed to load updates" }, { status: 500 })
  }
}

type CreateBody = {
  title?: string
  body?: string
  category?: string
  destination?: string
  sendPush?: boolean
  status?: "draft" | "scheduled"
  publishAt?: string | null
}

export async function POST(req: Request) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  let body: CreateBody
  try {
    body = (await req.json()) as CreateBody
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 })
  }

  const status = body.status === "scheduled" ? "scheduled" : "draft"
  const validation = validatePlatformUpdateInput({
    title: body.title,
    body: body.body,
    category: body.category,
    destination: body.destination,
    send_push: body.sendPush,
    status,
    publish_at: body.publishAt ?? null,
  })
  if (validation) {
    return Response.json({ error: validation }, { status: 400 })
  }

  if (!isPlatformUpdateCategoryId(body.category)) {
    return Response.json({ error: "Invalid category" }, { status: 400 })
  }
  if (!isPlatformUpdateDestinationId(body.destination)) {
    return Response.json({ error: "Invalid destination" }, { status: 400 })
  }

  const now = new Date().toISOString()
  const { data, error } = await supabaseServiceRole
    .from("platform_updates")
    .insert({
      title: body.title!.trim(),
      body: body.body!.trim(),
      category: body.category,
      destination: body.destination,
      send_push: body.sendPush === true,
      status,
      publish_at: status === "scheduled" ? body.publishAt : null,
      created_by: auth.adminUser.id,
      updated_at: now,
    })
    .select("*")
    .single()

  if (error || !data) {
    return Response.json({ error: error?.message ?? "Insert failed" }, { status: 500 })
  }

  return Response.json({
    update: serializeAdminUpdate({
      ...(data as PlatformUpdateRecord),
      broadcast: null,
    }),
  })
}
