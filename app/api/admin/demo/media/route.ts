import { createClient } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAdminApiUser } from "@/lib/requireAdminApi"
import {
  DEMO_MEDIA_BUCKET,
  demoMediaObjectPath,
  extensionForMime,
  isDemoMediaEntityType,
  isDemoOwnedStoragePath,
  resolvedMime,
  validateDemoMediaFile,
  type DemoMediaKind,
} from "@/lib/demo/demoMedia"

export const runtime = "nodejs"

async function referencedPaths(bearer: string): Promise<Set<string>> {
  const client = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${bearer}` } },
    }
  )
  const { data, error } = await client.rpc("rpc_v1_admin_demo_media_refs")
  if (error) {
    const forbidden = error.code === "42501" || /forbidden/i.test(error.message)
    throw new Response(JSON.stringify({ error: forbidden ? "Forbidden" : "Could not check Demo media references." }), {
      status: forbidden ? 403 : 500,
      headers: { "Content-Type": "application/json" },
    })
  }
  return new Set(Array.isArray(data) ? data.map(String) : [])
}

function bearerFrom(req: Request): string {
  return (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim()
}

export async function POST(req: Request) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error
  const bearer = bearerFrom(req)
  if (!bearer) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let form: FormData
  try {
    form = await req.formData()
  } catch {
    return Response.json({ error: "Upload was incomplete." }, { status: 400 })
  }

  const file = form.get("file")
  const entityType = String(form.get("entityType") || "")
  const entityId = String(form.get("entityId") || "")
  const kind = String(form.get("kind") || "")
  if (!(file instanceof File)) return Response.json({ error: "Choose a file to upload." }, { status: 400 })
  if (!isDemoMediaEntityType(entityType)) return Response.json({ error: "Unsupported Demo media type." }, { status: 400 })
  if (kind !== "image" && kind !== "video") return Response.json({ error: "Unsupported Demo media type." }, { status: 400 })

  const bytes = new Uint8Array(await file.arrayBuffer())
  const mime = resolvedMime({ name: file.name, type: file.type })
  const problem = validateDemoMediaFile(
    { name: file.name, type: file.type, size: file.size, bytes },
    { entityType, kind: kind as DemoMediaKind }
  )
  if (problem || !mime) return Response.json({ error: problem || "Unsupported Demo media file." }, { status: 400 })

  const extension = extensionForMime(mime)
  if (!extension) return Response.json({ error: "Unsupported Demo media file." }, { status: 400 })

  let path: string
  try {
    path = demoMediaObjectPath(entityType, entityId, extension)
  } catch (cause) {
    return Response.json({ error: cause instanceof Error ? cause.message : "Unsupported Demo media type." }, { status: 400 })
  }
  if (!isDemoOwnedStoragePath(path)) {
    return Response.json({ error: "Demo media path was rejected." }, { status: 400 })
  }

  const { error } = await supabaseServiceRole.storage.from(DEMO_MEDIA_BUCKET).upload(path, bytes, {
    contentType: mime,
    upsert: false,
  })
  if (error) {
    return Response.json({ error: "Upload failed. The current Demo media was left unchanged." }, { status: 500 })
  }

  const { data } = supabaseServiceRole.storage.from(DEMO_MEDIA_BUCKET).getPublicUrl(path)
  return Response.json({ url: data.publicUrl, path, kind })
}

export async function DELETE(req: Request) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error
  const bearer = bearerFrom(req)
  if (!bearer) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let body: { paths?: string[]; cleanup?: boolean }
  try {
    body = (await req.json()) as { paths?: string[]; cleanup?: boolean }
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 })
  }

  const requested = Array.isArray(body.paths) ? body.paths.map(String) : []
  if (requested.some((path) => !isDemoOwnedStoragePath(path))) {
    return Response.json({ error: "Only Demo-owned media can be removed." }, { status: 400 })
  }

  let referenced: Set<string>
  try {
    referenced = await referencedPaths(bearer)
  } catch (cause) {
    if (cause instanceof Response) return cause
    return Response.json({ error: "Could not check Demo media references." }, { status: 500 })
  }

  let candidates = requested.filter((path) => !referenced.has(path))
  if (body.cleanup) {
    const listed = await listDemoObjects()
    candidates = [...new Set([...candidates, ...listed.filter((path) => isDemoOwnedStoragePath(path) && !referenced.has(path))])]
  }

  if (!candidates.length) return Response.json({ removed: [] })
  const { error } = await supabaseServiceRole.storage.from(DEMO_MEDIA_BUCKET).remove(candidates)
  if (error) return Response.json({ error: "Demo media cleanup failed." }, { status: 500 })
  return Response.json({ removed: candidates })
}

async function listDemoObjects(): Promise<string[]> {
  const files: string[] = []
  async function walk(prefix: string) {
    const { data, error } = await supabaseServiceRole.storage.from(DEMO_MEDIA_BUCKET).list(prefix, { limit: 1000 })
    if (error || !data) return
    for (const item of data) {
      const path = prefix ? `${prefix}/${item.name}` : item.name
      if (item.id) files.push(path)
      else await walk(path)
    }
  }
  await walk("demo")
  return files
}
