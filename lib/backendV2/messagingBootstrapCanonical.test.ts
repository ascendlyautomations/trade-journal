import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { decodeMessagesBootstrapV1 } from "./contracts.ts"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Messaging inbox canonical RPC repair", () => {
  it("canonical migration reads public.messages not conversations.last_message_at", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /latest_messages as \(/)
    assert.match(sql, /from public\.messages m/)
    assert.match(sql, /order by m\.conversation_id, m\.created_at desc, m\.id desc/)
    assert.match(sql, /'last_message_id', p\.last_message_id/)
    assert.match(sql, /'last_message_sender_id', p\.last_message_sender_id/)
    assert.doesNotMatch(sql, /c\.last_message_at desc nulls last,\s*\n\s*c\.id desc/)
  })

  it("superseded trigger migration is a no-op", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826183000_conversations_sync_last_message_from_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /SUPERSEDED/)
    assert.doesNotMatch(sql, /create trigger/)
  })

  it("uses viewer-visible message filter aligned with thread bootstrap", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /message_deletions md/)
    assert.match(sql, /deleted_for_everyone/)
  })

  it("orders inbox by canonical message timestamp and id", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /lm\.created_at desc nulls last/)
    assert.match(sql, /lm\.message_id desc nulls last/)
  })

  it("latest_messages CTE does not exclude viewer-authored messages", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    const latestMessagesBlock = sql.slice(
      sql.indexOf("latest_messages as ("),
      sql.indexOf("ranked as (")
    )
    assert.doesNotMatch(latestMessagesBlock, /sender_id\s*<>\s*v_uid/)
    assert.doesNotMatch(latestMessagesBlock, /sender_id\s*!=\s*v_uid/)
    assert.doesNotMatch(latestMessagesBlock, /sender_id\s*<>\s*auth\.uid\(\)/)
    assert.match(sql, /Never filter m\.sender_id <> v_uid here/)
  })

  it("unread counts use separate get_conversation_unread_counts not latest_messages", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /get_conversation_unread_counts/)
    const unreadFn = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260718090000_phase1_messaging_scalability.sql"
      ),
      "utf8"
    )
    assert.match(unreadFn, /m\.sender_id <> cp\.user_id/)
  })

  it("preserves composite cursor contract conversation_id suffix", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260826210000_rpc_v2_messaging_bootstrap_canonical_messages.sql"
      ),
      "utf8"
    )
    assert.match(sql, /\|\| '\|'\s*\|\|/)
    assert.match(sql, /->> 'id'\)/)
  })

  it("decodes additive last_message_id on conversation rows", () => {
    const fixture = {
      meta: {
        contract_version: "v1",
        server_time: "2026-08-26T12:00:00.000Z",
        viewer_id: "viewer-1",
      },
      data: {
        conversations: [
          {
            id: "11111111-1111-1111-1111-111111111111",
            is_group: false,
            is_pinned: false,
            name: "Peer",
            avatar_url: null,
            last_message_id: "22222222-2222-2222-2222-222222222222",
            last_message_sender_id: "33333333-3333-3333-3333-333333333333",
            last_message_type: "text",
            last_message: "hello",
            last_message_at: "2026-08-26T12:00:00.000Z",
            unread_count: 0,
            muted: false,
            participants: [],
          },
        ],
        peers: {},
        dm_unread_total: 0,
        muted_ids: [],
        next_cursor: null,
        page_meta: { limit: 40, returned: 1, has_more: false },
      },
    }
    const decoded = decodeMessagesBootstrapV1(fixture)
    assert.equal(
      decoded.data.conversations[0]?.last_message_id,
      "22222222-2222-2222-2222-222222222222"
    )
    assert.equal(
      decoded.data.conversations[0]?.last_message_sender_id,
      "33333333-3333-3333-3333-333333333333"
    )
  })

  it("empty conversation decodes null latest activity fields", () => {
    const fixture = {
      meta: {
        contract_version: "v1",
        server_time: "2026-08-26T12:00:00.000Z",
        viewer_id: "viewer-1",
      },
      data: {
        conversations: [
          {
            id: "11111111-1111-1111-1111-111111111111",
            is_group: false,
            is_pinned: false,
            name: "Empty",
            avatar_url: null,
            last_message_id: null,
            last_message_sender_id: null,
            last_message_type: null,
            last_message: null,
            last_message_at: null,
            unread_count: 0,
            muted: false,
            participants: [],
          },
        ],
        peers: {},
        dm_unread_total: 0,
        muted_ids: [],
        next_cursor: null,
        page_meta: { limit: 40, returned: 1, has_more: false },
      },
    }
    const decoded = decodeMessagesBootstrapV1(fixture)
    const row = decoded.data.conversations[0]
    assert.equal(row?.last_message, null)
    assert.equal(row?.last_message_at, null)
    assert.equal(row?.last_message_id ?? null, null)
  })
})
export {}
