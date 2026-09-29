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
  status?: "draft" | "scheduled" | "cancelled"
  publishAt?: string | null
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
  if (existing.status === "published" || existing.status === "cancelled") {
    return Response.json(
      { error: "Published updates cannot be edited." },
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

  const nextStatus =
    body.status ??
    (existing.status as "draft" | "scheduled" | "cancelled")

  const merged = {
    title: body.title ?? existing.title,
    body: body.body ?? existing.body,
    category: body.category ?? existing.category,
    destination: body.destination ?? existing.destination,
    send_push: body.sendPush ?? existing.send_push,
    status: nextStatus,
    publish_at:
      body.publishAt !== undefined ? body.publishAt : existing.publish_at,
  }

  const validation = validatePlatformUpdateInput({
    title: merged.title,
    body: merged.body,
    category: merged.category,
    destination: merged.destination,
    send_push: merged.send_push,
    status: merged.status === "scheduled" ? "scheduled" : undefined,
    publish_at: merged.status === "scheduled" ? merged.publish_at : null,
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
      status: merged.status,
      publish_at: merged.status === "scheduled" ? merged.publish_at : null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", updateId)
    .in("status", ["draft", "scheduled"])
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
  const { error } = await supabaseServiceRole
    .from("platform_updates")
    .delete()
    .eq("id", id.trim())
    .eq("status", "draft")

  if (error) {
    return Response.json({ error: error.message }, { status: 500 })
  }
  return Response.json({ ok: true })
}
