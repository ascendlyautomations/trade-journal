import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"

type TabStatus = "pending" | "approved" | "rejected"

function parseStatus(v: string | null): TabStatus {
  if (v === "pending" || v === "approved" || v === "rejected") return v
  return "pending"
}

export async function GET(req: Request) {
  const url = new URL(req.url)
  const status = parseStatus(url.searchParams.get("status")?.trim().toLowerCase() ?? null)

  const { data, error } = await supabaseServiceRole
    .from("affiliate_applications")
    .select("*")
    .eq("status", status)
    .order("created_at", { ascending: false })

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }

  return new Response(JSON.stringify({ applications: data ?? [] }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  })
}
