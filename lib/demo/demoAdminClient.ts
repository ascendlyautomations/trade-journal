import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import type { DemoAdminState, DemoRecord } from "@/lib/demo/demoAdminModel"

async function command(name: string, payload: DemoRecord = {}): Promise<DemoAdminState> {
  const res = await fetch("/api/admin/demo", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify({ command: name, payload }),
  })
  const json = (await res.json()) as DemoAdminState & { error?: string }
  if (!res.ok) throw new Error(json.error || "Demo admin request failed")
  return json
}

export const demoAdminApi = {
  state: () => command("state"),
  validate: () => command("validate"),
  save: (entity: string, record: DemoRecord, extra: DemoRecord = {}) =>
    command("save", { entity, record, ...extra }),
  remove: (entity: string, payload: DemoRecord) => command("delete", { entity, ...payload }),
  reorder: (entity: string, ids: string[]) => command("reorder", { entity, ids }),
  publish: () => command("publish"),
  discard: () => command("discard"),
  restore: (version: number) => command("restore", { version }),
}

export async function uploadDemoMedia(input: {
  file: File
  entityType: string
  entityId: string
  kind: "image" | "video"
}): Promise<{ url: string; path: string; kind: string }> {
  const body = new FormData()
  body.set("file", input.file)
  body.set("entityType", input.entityType)
  body.set("entityId", input.entityId)
  body.set("kind", input.kind)
  const res = await fetch("/api/admin/demo/media", {
    method: "POST",
    headers: await supabaseBearerHeaders(),
    body,
  })
  const json = (await res.json()) as { url?: string; path?: string; kind?: string; error?: string }
  if (!res.ok || !json.url || !json.path) throw new Error(json.error || "Upload failed. The current Demo media was left unchanged.")
  return { url: json.url, path: json.path, kind: json.kind || input.kind }
}

export async function cleanupUnusedDemoMedia(): Promise<number> {
  const res = await fetch("/api/admin/demo/media", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify({ paths: [], cleanup: true }),
  })
  const json = (await res.json()) as { error?: string; removed?: string[] }
  if (!res.ok) throw new Error(json.error || "Demo media cleanup failed.")
  return json.removed?.length ?? 0
}

export async function releaseDemoMedia(paths: string[]): Promise<void> {
  const unique = [...new Set(paths.filter(Boolean))]
  if (!unique.length) return
  const res = await fetch("/api/admin/demo/media", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      ...(await supabaseBearerHeaders()),
    },
    body: JSON.stringify({ paths: unique }),
  })
  const json = (await res.json()) as { error?: string }
  if (!res.ok) throw new Error(json.error || "Demo media cleanup failed.")
}
