import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import type {
  PlatformUpdateCategoryId,
  PlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"

export type PlatformUpdatePublic = {
  id: string
  title: string
  body: string
  category: PlatformUpdateCategoryId
  destination: PlatformUpdateDestinationId
  href: string
  publishedAt: string | null
}

export type AdminPlatformUpdate = {
  id: string
  title: string
  body: string
  category: PlatformUpdateCategoryId
  destination: PlatformUpdateDestinationId
  destinationHref: string
  sendPush: boolean
  status: string
  publishAt: string | null
  publishedAt: string | null
  createdAt: string
  updatedAt: string
  broadcast: {
    id: string
    status: string
    attemptedCount: number
    successCount: number
    failedCount: number
    startedAt: string | null
    completedAt: string | null
  } | null
}

async function parseJson(res: Response) {
  return (await res.json()) as Record<string, unknown>
}

export async function fetchPublishedPlatformUpdates(): Promise<
  PlatformUpdatePublic[]
> {
  const res = await fetch("/api/platform-updates", {
    headers: { ...(await supabaseBearerHeaders()) },
  })
  const json = await parseJson(res)
  if (!res.ok) throw new Error(String(json.error ?? "Failed to load"))
  return (json.updates as PlatformUpdatePublic[]) ?? []
}

export async function fetchAdminPlatformUpdates(): Promise<AdminPlatformUpdate[]> {
  const res = await fetch("/api/admin/platform-updates", {
    headers: { ...(await supabaseBearerHeaders()) },
  })
  const json = await parseJson(res)
  if (!res.ok) throw new Error(String(json.error ?? "Failed to load"))
  return (json.updates as AdminPlatformUpdate[]) ?? []
}

export async function createAdminPlatformUpdate(input: {
  title: string
  body: string
  category: PlatformUpdateCategoryId
  destination: PlatformUpdateDestinationId
  sendPush: boolean
  status: "draft" | "scheduled"
  publishAt?: string | null
}): Promise<AdminPlatformUpdate> {
  const res = await fetch("/api/admin/platform-updates", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify({
      title: input.title,
      body: input.body,
      category: input.category,
      destination: input.destination,
      sendPush: input.sendPush,
      status: input.status,
      publishAt: input.publishAt ?? null,
    }),
  })
  const json = await parseJson(res)
  if (!res.ok) throw new Error(String(json.error ?? "Create failed"))
  return json.update as AdminPlatformUpdate
}

export async function patchAdminPlatformUpdate(
  id: string,
  input: Record<string, unknown>
): Promise<AdminPlatformUpdate> {
  const res = await fetch(`/api/admin/platform-updates/${id}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify(input),
  })
  const json = await parseJson(res)
  if (!res.ok) throw new Error(String(json.error ?? "Save failed"))
  return json.update as AdminPlatformUpdate
}

export async function deleteAdminPlatformUpdateDraft(id: string): Promise<void> {
  const res = await fetch(`/api/admin/platform-updates/${id}`, {
    method: "DELETE",
    headers: { ...(await supabaseBearerHeaders()) },
  })
  if (!res.ok) {
    const json = await parseJson(res)
    throw new Error(String(json.error ?? "Delete failed"))
  }
}

export async function publishAdminPlatformUpdate(id: string): Promise<{
  publishSucceeded: boolean
  pushSucceeded: boolean
  pushDelivery: {
    broadcastId: string
    status: string
    attemptedCount: number
    successCount: number
    failedCount: number
    apnsConfigured: boolean
    apnsProduction: boolean
    iosTokenRows: number
    incomplete: boolean
    lastApnsFailureReason: string | null
  } | null
}> {
  const res = await fetch(`/api/admin/platform-updates/${id}/publish`, {
    method: "POST",
    headers: { ...(await supabaseBearerHeaders()) },
  })
  const json = await parseJson(res)
  if (!res.ok) throw new Error(String(json.error ?? "Publish failed"))
  return {
    publishSucceeded: Boolean(json.publishSucceeded ?? json.ok),
    pushSucceeded: Boolean(json.pushSucceeded),
    pushDelivery: (json.pushDelivery as {
      broadcastId: string
      status: string
      attemptedCount: number
      successCount: number
      failedCount: number
      apnsConfigured: boolean
      apnsProduction: boolean
      iosTokenRows: number
      incomplete: boolean
      lastApnsFailureReason: string | null
    } | null) ?? null,
  }
}
