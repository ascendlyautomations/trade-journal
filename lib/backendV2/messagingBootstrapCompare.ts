/**
 * Dual-run compare for Messaging bootstrap (REST vs RPC).
 */

import type { MessagesBootstrapV1 } from "./contracts.ts"

export type MessagingBootstrapMismatch = {
  path: string
  rest: unknown
  rpc: unknown
}

export function compareMessagingBootstraps(
  rest: MessagesBootstrapV1,
  rpc: MessagesBootstrapV1
): MessagingBootstrapMismatch[] {
  const mismatches: MessagingBootstrapMismatch[] = []
  const restIds = rest.data.conversations.map((c) => c.id).sort()
  const rpcIds = rpc.data.conversations.map((c) => c.id).sort()
  if (JSON.stringify(restIds) !== JSON.stringify(rpcIds)) {
    mismatches.push({
      path: "conversations.ids",
      rest: restIds,
      rpc: rpcIds,
    })
  }
  if (rest.data.dm_unread_total !== rpc.data.dm_unread_total) {
    mismatches.push({
      path: "dm_unread_total",
      rest: rest.data.dm_unread_total,
      rpc: rpc.data.dm_unread_total,
    })
  }
  return mismatches
}

export function logMessagingBootstrapMismatches(
  mismatches: MessagingBootstrapMismatch[]
): void {
  if (mismatches.length === 0) return
  console.warn(
    `[backendV2.messages] dual-run mismatches (${mismatches.length})`,
    mismatches
  )
}
