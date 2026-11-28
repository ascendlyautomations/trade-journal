import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import {
  createPortfolioConversation,
  openTradeConversation,
} from "@/lib/server/ai/aiConversationService"
import type { AiPortfolioScope } from "@/lib/server/ai/aiConversationTypes"

export const runtime = "nodejs"

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const entitlement = await requireAIFeatureEntitlement(user.id)
  if (!entitlement.ok) {
    return entitlement.response
  }

  let body: {
    kind?: "trade" | "general_trade"
    tradeId?: string
    title?: string
    scope?: AiPortfolioScope
  }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 })
  }

  if (body.kind === "trade" && body.tradeId) {
    const opened = await openTradeConversation(
      supabaseServiceRole,
      user.id,
      body.tradeId
    )
    if (opened.error) {
      return NextResponse.json({ error: opened.error }, { status: 403 })
    }
    return NextResponse.json({ conversationId: opened.conversationId, kind: "trade" })
  }

  const scope = body.scope ?? { preset: "all_time", accountIds: "all" }
  const created = await createPortfolioConversation(
    supabaseServiceRole,
    user.id,
    body.title?.trim() || "General Trade AI",
    scope
  )
  if (created.error) {
    return NextResponse.json({ error: created.error }, { status: 500 })
  }
  return NextResponse.json({
    conversationId: created.conversationId,
    kind: "general_trade",
  })
}