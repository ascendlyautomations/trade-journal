import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import {
  mutateTradovateConnectionPendingLink,
  parseTradovatePendingLinkHttpBody,
} from "@/lib/integrations/tradovate/tradovateConnectionPendingLinkHttp"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

export async function GET(_req: Request, context: RouteContext) {
  const user = await getRouteUser(_req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "tradovate",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  const { loadBrokerConnectionPendingLink } = await import(
    "@/lib/integrations/brokerConnectionPendingLink"
  )
  const pendingLink = await loadBrokerConnectionPendingLink(integrationDb, {
    userId: user.id,
    connectionId,
  })

  return Response.json({ connectionId, pendingLink })
}

export async function POST(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "tradovate",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const pendingBody = parseTradovatePendingLinkHttpBody(body)
  if (!pendingBody?.action) {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  return mutateTradovateConnectionPendingLink(integrationDb, {
    userId: user.id,
    connectionId,
    body: pendingBody,
  })
}

export async function DELETE(_req: Request, context: RouteContext) {
  const user = await getRouteUser(_req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "tradovate",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  return mutateTradovateConnectionPendingLink(integrationDb, {
    userId: user.id,
    connectionId,
    body: { action: "clear" },
  })
}