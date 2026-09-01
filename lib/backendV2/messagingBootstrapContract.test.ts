import { describe, it } from "node:test"
import { decodeMessagesBootstrapV1 } from "./contracts.ts"
import { messagesBootstrapFixture } from "./fixtures.ts"
import { messagingContractFixtures } from "./messagingContractFixtures.ts"
import { validateMessagingBootstrapContract, isCompositeMessagingCursor, compareMessagingBootstrapSemantics, } from "./messagingContractSchema.ts"
import { compareMessagingBootstraps } from "./messagingBootstrapCompare.ts"
import { isMessagingV2Unavailable, v1CursorFromComposite, } from "./messagingRpcCompat.ts"
import { BackendV2RpcError } from "./rpcClient.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

const CASES = [
  ["emptyInbox", messagingContractFixtures.emptyInbox],
  ["singlePersonal", messagingContractFixtures.singlePersonal],
  ["groupConversation", messagingContractFixtures.groupConversation],
  ["mutedConversation", messagingContractFixtures.mutedConversation],
  ["paginationBoundary", messagingContractFixtures.paginationBoundary],
  ["equalTimestampBoundary", messagingContractFixtures.equalTimestampBoundary],
  ["inboxOpenMarkRead", messagingContractFixtures.inboxOpenMarkRead],
  ["noMessagesYet", messagingContractFixtures.noMessagesYet],
  ["goldenFixture", messagesBootstrapFixture],
]

describe("Phase C — Messaging bootstrap contract shape", () => {
  for (const [name, fixture] of CASES) {
    it(`validates ${name} fixture shape`, () => {
      const decoded = decodeMessagesBootstrapV1(
        JSON.parse(JSON.stringify(fixture))
      )
      const violations = validateMessagingBootstrapContract(decoded)
      assert.deepEqual(
        violations,
        [],
        `${name}: ${violations.map((v) => v.path).join(", ")}`
      )
    })
  }

  it("composite cursor format is recognized", () => {
    assert.equal(
      isCompositeMessagingCursor(
        "2026-08-20T12:00:00.000Z|11111111-1111-1111-1111-111111111111"
      ),
      true
    )
    assert.equal(isCompositeMessagingCursor("2026-08-20T12:00:00.000Z"), false)
  })

  it("v1CursorFromComposite strips conversation id suffix", () => {
    assert.equal(
      v1CursorFromComposite(
        "2026-08-20T12:00:00.000Z|11111111-1111-1111-1111-111111111111"
      ),
      "2026-08-20T12:00:00.000Z"
    )
    assert.equal(v1CursorFromComposite("2026-08-20T12:00:00.000Z"), "2026-08-20T12:00:00.000Z")
  })

  it("isMessagingV2Unavailable detects missing function errors", () => {
    assert.equal(
      isMessagingV2Unavailable(
        new BackendV2RpcError(
          "PGRST202",
          "Could not find the function public.rpc_v2_messaging_bootstrap",
          "rpc_v2_messaging_bootstrap"
        )
      ),
      true
    )
    assert.equal(
      isMessagingV2Unavailable(
        new BackendV2RpcError("42501", "not_authenticated", "rpc_v2_messaging_bootstrap")
      ),
      false
    )
  })

  it("semantic compare ignores server_time and mark-read count", () => {
    const a = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagingContractFixtures.singlePersonal))
    )
    const b = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagingContractFixtures.singlePersonal))
    )
    b.meta.server_time = "2099-01-01T00:00:00.000Z"
    b.data.message_notifications_marked_read = 9
    assert.deepEqual(compareMessagingBootstrapSemantics(a, b), [])
  })

  it("compare helper detects conversation id drift", () => {
    const a = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagingContractFixtures.singlePersonal))
    )
    const b = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagingContractFixtures.singlePersonal))
    )
    b.data.conversations = []
    const mismatches = compareMessagingBootstraps(a, b)
    assert.ok(mismatches.some((m) => m.path === "conversations.ids"))
  })
})

describe("Phase C hardening — V2 migration + rollback", () => {
  it("V2 migration leaves V1 untouched and requires explicit args", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260821014228_rpc_v2_messaging_bootstrap.sql"
      ),
      "utf8"
    )
    assert.match(sql, /create or replace function public\.rpc_v2_messaging_bootstrap\(/)
    assert.match(sql, /p_mark_message_notifications_read boolean/)
    assert.match(sql, /search_path = public, pg_temp/)
    assert.match(sql, /revoke all on function public\.rpc_v2_messaging_bootstrap.* from anon/)
    assert.doesNotMatch(sql, /drop function if exists public\.rpc_v1_messaging_bootstrap/)
    assert.doesNotMatch(sql, /create or replace function public\.rpc_v1_messaging_bootstrap/)
  })

  it("rollback drops V2 only", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/rollback/20260821014228_rpc_v2_messaging_bootstrap_rollback.sql"
      ),
      "utf8"
    )
    assert.match(sql, /drop function if exists public\.rpc_v2_messaging_bootstrap/)
    assert.doesNotMatch(sql, /rpc_v1_messaging_bootstrap/)
  })

  it("original V1 migration still exposes timestamptz cursor", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260821090000_rpc_v1_messaging_bootstrap.sql"
      ),
      "utf8"
    )
    assert.match(sql, /p_cursor timestamptz default null/)
  })
})

describe("Phase C — Messages client loading wiring", () => {
  it("inbox consolidates mark-read into bootstrap when V2 ON", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../../app/(app)/messages/page.tsx"),
      "utf8"
    )
    assert.match(src, /markMessageNotificationsRead: markOnOpen/)
    assert.match(src, /inboxRequestGenerationRef/)
    assert.match(src, /message_notifications_marked_read/)
  })

  it("repository calls V2 with V1 fallback", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "messagingBootstrapRepository.ts"),
      "utf8"
    )
    assert.match(src, /p_mark_message_notifications_read/)
    assert.match(src, /BackendV2RpcNames\.messagingV1/)
    assert.match(src, /needsMarkRead/)
  })

  it("native-ios references V2 messaging RPC", () => {
    const src = fs.readFileSync(
      path.join(
        __dirname,
        "../../native-ios/TradeTraxs/TradeTraxs/Data/BackendV2/BackendV2Versioning.swift"
      ),
      "utf8"
    )
    assert.match(src, /rpc_v2_messaging_bootstrap/)
  })
})
export {}
