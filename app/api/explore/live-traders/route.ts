import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listExploreLiveTradersNow } from "@/lib/livekit/exploreLiveTradersNow.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** Public discover feed — only public, non-private-room broadcasts are returned. */
export async function GET(req: Request) {
  const url = new URL(req.url)
  const limit = Math.min(
    24,
    Math.max(1, Number.parseInt(url.searchParams.get("limit") ?? "12", 10) || 12)
  )

  try {
    const items = await listExploreLiveTradersNow(supabaseServiceRole, {
      limit,
      includeViewerCounts: true,
    })
    return Response.json({ items })
  } catch (error) {
    console.error("[explore/live-traders]", error)
    return Response.json(
      { items: [], error: "Could not load live traders." },
      { status: 500 }
    )
  }
}
