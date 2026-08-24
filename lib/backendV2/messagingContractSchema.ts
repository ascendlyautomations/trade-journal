/**
 * Phase C: Messaging bootstrap contract validators.
 */

import type { MessagesBootstrapV1 } from "./contracts.ts"

export type MessagingContractViolation = {
  path: string
  message: string
  expected?: string
  actual?: string
}

const CONVERSATION_KINDS = ["personal", "group"] as const

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function requireType(
  value: unknown,
  expected: string,
  path: string,
  out: MessagingContractViolation[]
): void {
  const actual =
    value === null ? "null" : Array.isArray(value) ? "array" : typeof value
  if (actual !== expected) {
    out.push({ path, message: "type mismatch", expected, actual })
  }
}

export function isCompositeMessagingCursor(value: string): boolean {
  const parts = value.split("|")
  if (parts.length !== 2) return false
  return /^[0-9a-f-]{36}$/i.test(parts[1] ?? "")
}

/** Validates Messaging bootstrap v1 wire contract (ignores meta.server_time). */
export function validateMessagingBootstrapContract(
  raw: MessagesBootstrapV1
): MessagingContractViolation[] {
  const v: MessagingContractViolation[] = []

  if (raw.meta.contract_version !== "v1") {
    v.push({
      path: "meta.contract_version",
      message: "must be v1",
      expected: "v1",
      actual: String(raw.meta.contract_version),
    })
  }

  requireType(raw.meta.viewer_id, "string", "meta.viewer_id", v)

  const data = raw.data
  requireType(data.conversations, "array", "data.conversations", v)
  requireType(data.peers, "object", "data.peers", v)
  requireType(data.dm_unread_total, "number", "data.dm_unread_total", v)
  requireType(data.muted_ids, "array", "data.muted_ids", v)
  if (data.next_cursor !== null) {
    requireType(data.next_cursor, "string", "data.next_cursor", v)
  }

  if (data.message_notifications_marked_read != null) {
    requireType(
      data.message_notifications_marked_read,
      "number",
      "data.message_notifications_marked_read",
      v
    )
  }

  requireType(data.page_meta, "object", "data.page_meta", v)
  requireType(data.page_meta.limit, "number", "data.page_meta.limit", v)
  requireType(data.page_meta.returned, "number", "data.page_meta.returned", v)
  requireType(data.page_meta.has_more, "boolean", "data.page_meta.has_more", v)

  if (data.page_meta.returned !== data.conversations.length) {
    v.push({
      path: "data.page_meta.returned",
      message: "must equal conversations.length",
      expected: String(data.conversations.length),
      actual: String(data.page_meta.returned),
    })
  }

  for (const [i, conv] of data.conversations.entries()) {
    const prefix = `data.conversations[${i}]`
    requireType(conv.id, "string", `${prefix}.id`, v)
    requireType(conv.is_group, "boolean", `${prefix}.is_group`, v)
    requireType(conv.unread_count, "number", `${prefix}.unread_count`, v)
    requireType(conv.muted, "boolean", `${prefix}.muted`, v)
    requireType(conv.participants, "array", `${prefix}.participants`, v)
    if (conv.muted && conv.unread_count !== 0) {
      v.push({
        path: `${prefix}.unread_count`,
        message: "muted conversations must expose unread_count 0",
        actual: String(conv.unread_count),
      })
    }
  }

  return v
}

export function compareMessagingBootstrapSemantics(
  a: MessagesBootstrapV1,
  b: MessagesBootstrapV1
): MessagingContractViolation[] {
  const strip = (m: MessagesBootstrapV1) => {
    const copy = JSON.parse(JSON.stringify(m)) as MessagesBootstrapV1
    copy.meta.server_time = "FIXED"
    delete copy.data.message_notifications_marked_read
    return copy
  }
  if (JSON.stringify(strip(a)) !== JSON.stringify(strip(b))) {
    return [{ path: "root", message: "semantic payload differs" }]
  }
  return []
}
