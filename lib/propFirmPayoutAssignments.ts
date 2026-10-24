import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"

const PAYOUT_KEY = /^(ledger|cycle|achievement):[0-9a-fA-F-]{36}$/
const NAME_MAX = 120

let assignmentCache: { userId: string; names: Record<string, string> } | null = null
const listeners = new Set<() => void>()

export function isPropFirmPayoutKey(value: string): boolean {
  return PAYOUT_KEY.test(value)
}

export function normalizePropFirmAssignmentName(value: string): string | null {
  const name = value.trim()
  if (!name || name.length > NAME_MAX) return null
  return name
}

export function peekPropFirmPayoutAssignments(userId: string): Record<string, string> {
  if (assignmentCache?.userId !== userId) return {}
  return assignmentCache.names
}

export function subscribePropFirmPayoutAssignments(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

function publish(userId: string, names: Record<string, string>) {
  assignmentCache = { userId, names }
  for (const listener of listeners) listener()
}

export async function loadPropFirmPayoutAssignments(
  client: SupabaseClient<Database>,
  userId: string,
  options?: { force?: boolean }
): Promise<Record<string, string>> {
  if (!options?.force && assignmentCache?.userId === userId) return assignmentCache.names
  const { data, error } = await client
    .from("prop_firm_payout_assignments")
    .select("payout_key,prop_firm_name")
    .eq("user_id", userId)
  if (error || !data) return assignmentCache?.userId === userId ? assignmentCache.names : {}
  const names: Record<string, string> = {}
  for (const row of data) {
    const firm = normalizePropFirmAssignmentName(row.prop_firm_name)
    if (firm && isPropFirmPayoutKey(row.payout_key)) names[row.payout_key] = firm
  }
  publish(userId, names)
  return names
}

export async function savePropFirmPayoutAssignment(
  client: SupabaseClient<Database>,
  userId: string,
  payoutKey: string,
  firmName: string
): Promise<string | null> {
  if (!isPropFirmPayoutKey(payoutKey)) return "That payout cannot be assigned."
  const name = normalizePropFirmAssignmentName(firmName)
  if (!name) return "Enter a prop firm name."
  const { error } = await client.from("prop_firm_payout_assignments").upsert(
    { user_id: userId, payout_key: payoutKey, prop_firm_name: name },
    { onConflict: "user_id,payout_key" }
  )
  if (error) return "Couldn't save the prop firm for that payout."
  const names = { ...(assignmentCache?.userId === userId ? assignmentCache.names : {}), [payoutKey]: name }
  publish(userId, names)
  return null
}

export async function clearPropFirmPayoutAssignment(
  client: SupabaseClient<Database>,
  userId: string,
  payoutKey: string
): Promise<string | null> {
  if (!isPropFirmPayoutKey(payoutKey)) return "That payout cannot be assigned."
  const { error } = await client
    .from("prop_firm_payout_assignments")
    .delete()
    .eq("user_id", userId)
    .eq("payout_key", payoutKey)
  if (error) return "Couldn't remove that prop firm assignment."
  const names = { ...(assignmentCache?.userId === userId ? assignmentCache.names : {}) }
  delete names[payoutKey]
  publish(userId, names)
  return null
}
