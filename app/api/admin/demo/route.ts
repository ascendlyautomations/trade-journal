import { createClient } from "@supabase/supabase-js"
import { requireAdminApiUser } from "@/lib/requireAdminApi"

export const runtime = "nodejs"

const COMMANDS = new Set([
  "state",
  "validate",
  "save",
  "delete",
  "reorder",
  "publish",
  "discard",
  "restore",
])

export async function POST(req: Request) {
  const auth = await requireAdminApiUser(req)
  if (auth.error) return auth.error

  const bearer = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim()
  if (!bearer) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: { command?: string; payload?: Record<string, unknown> }
  try {
    body = (await req.json()) as { command?: string; payload?: Record<string, unknown> }
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 })
  }

  const command = body.command || "state"
  if (!COMMANDS.has(command)) {
    return Response.json({ error: "Unknown Demo command" }, { status: 400 })
  }

  const client = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${bearer}` } },
    }
  )

  const { data, error } = await client.rpc("rpc_v1_admin_demo", {
    p_command: command,
    p_payload: body.payload ?? {},
  })

  if (error) {
    const forbidden = error.code === "42501" || /forbidden/i.test(error.message)
    return Response.json(
      { error: forbidden ? "Forbidden" : "Demo admin request failed" },
      { status: forbidden ? 403 : 500 }
    )
  }

  return Response.json(data ?? { ok: false, error: "Empty Demo response" })
}
