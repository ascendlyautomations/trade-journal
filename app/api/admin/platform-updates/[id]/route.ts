import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAdminApiUser } from "@/lib/requireAdminApi"
import {
  isPlatformUpdateCategoryId,
  isPlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import {
  getPlatformUpdateBroadcast,
  serializeAdminPlatformUpdate,
  validatePlatformUpdateInput,
  type PlatformUpdateRecord,
} from "@/lib/server/platformUpdates/platformUpdateService"

export const runtime = "nodejs"

type RouteContext = { params: Promise<{ id: string }> }

async function loadUpdate(id: string) {
  const { data } = await supabaseServiceRole
    .from("platform_updates")
    .select("*")
    .eq("id", id)
    .maybeSingle()
  return data
}

export async function GET(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { id } = await context.params
  const update = await loadUpdate(id.trim())
  if (!update) {
    return Response.json({ error: "Not found" }, { status: 404 })
  }
  const broadcast = await getPlatformUpdateBroadcast(supabaseServiceRole, update.id)
  return Response.json({
    update: serializeAdminPlatformUpdate(
      update as PlatformUpdateRecord,
      broadcast
    ),
  })
}

type PatchBody = {
  title?: string
  body?: string
  category?: string
  destination?: string
  sendPush?: boolean
}

export async function PATCH(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { id } = await context.params
  const updateId = id.trim()
  const existing = await loadUpdate(updateId)
  if (!existing) {
    return Response.json({ error: "Not found" }, { status: 404 })
  }
  if (existing.status !== "draft") {
    return Response.json(
      { error: "Only draft updates can be edited." },
      { status: 409 }
    )
  }

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 })
  }

  if (
    typeof raw === "object" &&
    raw !== null &&
    (raw as { status?: string }).status === "published"
  ) {
    return Response.json({ error: "Use publish endpoint." }, { status: 400 })
  }

  const body = raw as PatchBody

  const merged = {
    title: body.title ?? existing.title,
    body: body.body ?? existing.body,
    category: body.category ?? existing.category,
    destination: body.destination ?? existing.destination,
    send_push: body.sendPush ?? existing.send_push,
    status: "draft" as const,
    publish_at: null,
  }

  const validation = validatePlatformUpdateInput({
    title: merged.title,
    body: merged.body,
    category: merged.category,
    destination: merged.destination,
    send_push: merged.send_push,
  })
  if (validation) {
    return Response.json({ error: validation }, { status: 400 })
  }

  if (!isPlatformUpdateCategoryId(merged.category)) {
    return Response.json({ error: "Invalid category" }, { status: 400 })
  }
  if (!isPlatformUpdateDestinationId(merged.destination)) {
    return Response.json({ error: "Invalid destination" }, { status: 400 })
  }

  const { data, error } = await supabaseServiceRole
    .from("platform_updates")
    .update({
      title: merged.title.trim(),
      body: merged.body.trim(),
      category: merged.category,
      destination: merged.destination,
      send_push: merged.send_push === true,
      status: "draft",
      publish_at: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", updateId)
    .eq("status", "draft")
    .select("*")
    .single()

  if (error || !data) {
    return Response.json({ error: error?.message ?? "Update failed" }, { status: 500 })
  }

  const broadcast = await getPlatformUpdateBroadcast(supabaseServiceRole, updateId)
  return Response.json({
    update: serializeAdminPlatformUpdate(data as PlatformUpdateRecord, broadcast),
  })
}

export async function DELETE(req: Request, context: RouteContext) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const { id } = await context.params
  const updateId = id.trim()
  const { data, error } = await supabaseServiceRole
    .from("platform_updates")
    .delete()
    .eq("id", updateId)
    .in("status", ["draft", "published"])
    .select("id")

  if (error) {
    return Response.json({ error: error.message }, { status: 500 })
  }
  if (!data?.length) {
    return Response.json(
      { error: "Update not found or cannot be deleted." },
      { status: 404 }
    )
  }
  return Response.json({ ok: true })
}
