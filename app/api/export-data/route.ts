import { NextResponse } from "next/server"
import { createClient } from "@supabase/supabase-js"

export async function GET(req: Request) {
  const authHeader = req.headers.get("authorization")

  if (!authHeader) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const token = authHeader.replace("Bearer ", "")

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )

  const {
    data: { user },
  } = await supabase.auth.getUser(token)

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: trades } = await supabase
    .from("trades")
    .select("*")
    .eq("user_id", user.id)

  const csvRows: string[] = []

  if (trades && trades.length > 0) {
    const headers = Object.keys(trades[0])
    csvRows.push(headers.join(","))

    for (const row of trades) {
      csvRows.push(
        headers
          .map((h) => JSON.stringify((row as Record<string, unknown>)[h] ?? ""))
          .join(",")
      )
    }
  }

  const csv = csvRows.join("\n")

  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv",
      "Content-Disposition": "attachment; filename=tradetrax_data.csv",
    },
  })
}
