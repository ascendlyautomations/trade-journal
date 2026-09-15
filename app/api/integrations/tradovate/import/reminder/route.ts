import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type Body = {
  optOut?: boolean
}

export async function PATCH(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body = {}
  try {
    body = (await req.json()) as Body
  } catch {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  if (body.optOut !== true) {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const { error } = await integrationDb
    .from("profiles")
    .update({ tradovate_login_import_reminder_opt_out: true })
    .eq("id", user.id)

  if (error) {
    return Response.json({ error: "Could not save preference." }, { status: 500 })
  }

  return Response.json({ ok: true, optOut: true })
}
