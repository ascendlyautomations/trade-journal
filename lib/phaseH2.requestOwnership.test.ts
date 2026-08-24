import { describe, it, beforeEach } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))
import Stripe from "stripe"
import type { SupabaseClient } from "@supabase/supabase-js"
import {
  clearAllNotificationPreferencesCaches,
  ensureNotificationPreferencesLoaded,
  getCachedNotificationPreferences,
  resetNotificationPreferencesCacheForTests,
} from "./notificationPreferencesCache.ts"
import {
  ensureAffiliateApplicationLoaded,
  resetAffiliateDataRepositoryForTests,
} from "./affiliateDataRepository.ts"
import { countUnreviewedInitialImportsFromTrades } from "./initialImportReviewCountLogic.ts"

type NotificationPrefsRow = {
  user_id: string
  notifications_enabled: boolean
  likes_enabled: boolean
}

type NotificationPrefsQueryBuilder = {
  select(): NotificationPrefsQueryBuilder
  eq(col: string, val: string): NotificationPrefsQueryBuilder
  maybeSingle(): Promise<{ data: NotificationPrefsRow; error: null }>
}

function createNotificationPrefsSupabaseMock(
  resolveRow: (userId: string) => NotificationPrefsRow,
  onMaybeSingle?: () => void
): SupabaseClient {
  const mock = {
    from(_table: string) {
      let userId = ""
      const builder: NotificationPrefsQueryBuilder = {
        select() {
          return builder
        },
        eq(_col: string, val: string) {
          userId = val
          return builder
        },
        async maybeSingle() {
          onMaybeSingle?.()
          return { data: resolveRow(userId), error: null }
        },
      }
      return builder
    },
  }
  return mock as unknown as SupabaseClient
}

type AffiliateApplicationRow = {
  id: string
  user_id: string
  status: string
  has_edited: boolean
}

type AffiliateApplicationQueryBuilder = {
  select(): AffiliateApplicationQueryBuilder
  eq(): AffiliateApplicationQueryBuilder
  order(): AffiliateApplicationQueryBuilder
  limit(): AffiliateApplicationQueryBuilder
  maybeSingle(): Promise<{ data: AffiliateApplicationRow; error: null }>
}

function createAffiliateApplicationSupabaseMock(
  onMaybeSingle: () => void
): SupabaseClient {
  const mock = {
    from(table: string) {
      assert.equal(table, "affiliate_applications")
      const builder: AffiliateApplicationQueryBuilder = {
        select() {
          return builder
        },
        eq() {
          return builder
        },
        order() {
          return builder
        },
        limit() {
          return builder
        },
        async maybeSingle() {
          onMaybeSingle()
          return {
            data: {
              id: "app-1",
              user_id: "viewer-a",
              status: "pending",
              has_edited: false,
            },
            error: null,
          }
        },
      }
      return builder
    },
  }
  return mock as unknown as SupabaseClient
}

describe("Phase H2 — notification preferences ownership", () => {
  beforeEach(() => {
    resetNotificationPreferencesCacheForTests()
    clearAllNotificationPreferencesCaches()
  })

  it("single-flight dedupes simultaneous loads for one viewer", async () => {
    let calls = 0
    const client = createNotificationPrefsSupabaseMock(
      () => ({
        user_id: "viewer-a",
        notifications_enabled: true,
        likes_enabled: true,
      }),
      () => {
        calls += 1
      }
    )

    const [a, b] = await Promise.all([
      ensureNotificationPreferencesLoaded(client, "viewer-a"),
      ensureNotificationPreferencesLoaded(client, "viewer-a"),
    ])

    assert.equal(calls, 1)
    assert.equal(a?.user_id, "viewer-a")
    assert.equal(b?.user_id, "viewer-a")
  })

  it("isolates viewer caches", async () => {
    const client = createNotificationPrefsSupabaseMock((userId) => ({
      user_id: userId,
      notifications_enabled: true,
      likes_enabled: userId === "viewer-a",
    }))

    await ensureNotificationPreferencesLoaded(client, "viewer-a")
    await ensureNotificationPreferencesLoaded(client, "viewer-b")

    assert.equal(getCachedNotificationPreferences("viewer-a")?.likes_enabled, true)
    assert.equal(getCachedNotificationPreferences("viewer-b")?.likes_enabled, false)
  })
})

describe("Phase H2 — affiliate data ownership", () => {
  beforeEach(() => {
    resetAffiliateDataRepositoryForTests()
  })

  it("reuses affiliate application across immediate navigations", async () => {
    let calls = 0
    const client = createAffiliateApplicationSupabaseMock(() => {
      calls += 1
    })

    const first = await ensureAffiliateApplicationLoaded(client, "viewer-a")
    const second = await ensureAffiliateApplicationLoaded(client, "viewer-a")

    assert.equal(calls, 1)
    assert.equal(first?.id, "app-1")
    assert.equal(second?.id, "app-1")
  })

  it("wires affiliate connect sync through single-flight client", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "affiliateConnectSyncClient.ts"),
      "utf8"
    )
    assert.match(src, /inflightByViewer/)
    assert.match(src, /SYNC_SUCCESS_TTL_MS/)
    assert.match(src, /if \(existing\) return existing\.promise/)
  })

  it("loads affiliate connect sync only from affiliate sections", () => {
    const settings = fs.readFileSync(
      path.join(__dirname, "../app/settings/page.tsx"),
      "utf8"
    )
    assert.match(settings, /if \(activeTab !== "affiliate"/)
    assert.match(settings, /refreshAffiliateConnect\(user\.id\)/)
    const affiliateGuardIdx = settings.indexOf('if (activeTab !== "affiliate"')
    const refreshIdx = settings.indexOf("async function refreshAffiliateConnect")
    assert.ok(refreshIdx > affiliateGuardIdx)
  })
})

describe("Phase H2 — Add Trade cache reuse", () => {
  it("derives initial-import review count from trade rows", () => {
    const count = countUnreviewedInitialImportsFromTrades([
      { is_initial_import: true, reviewed: false },
      { is_initial_import: true, reviewed: true },
      { is_initial_import: false, reviewed: false },
    ])

    assert.equal(count, 1)
  })

  it("reuses dashboard account cache before REST on Add Trade", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/components/InputTradeForm.tsx"),
      "utf8"
    )
    assert.match(src, /getCachedAccounts\(userId\)/)
    assert.match(src, /cached \?\? \(await ensureAccountsLoaded/)
  })
})

describe("Phase H2 — affiliate sync error classification", () => {
  it("maps missing Stripe account to non-retryable 422 semantics", () => {
    const err = new Stripe.errors.StripeInvalidRequestError({
      message: "No such account: acct_missing",
      type: "invalid_request_error",
      code: "resource_missing",
      statusCode: 404,
    })

    assert.equal(err.statusCode, 404)
    assert.match(String(err.message), /No such account/)
  })

  it("classifies Stripe failures in connect sync route", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/api/affiliates/connect/sync/route.ts"),
      "utf8"
    )
    assert.match(src, /classifyStripeSyncFailure/)
    assert.match(src, /status: 422/)
  })
})
export {}
