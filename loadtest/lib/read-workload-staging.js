/**
 * Staging phase-A workload — reuses production read paths + staging-only routes.
 */

import http from "k6/http"
import { RPC_NAMES } from "./constants.js"
import { assertHttpOk, httpParams, supabaseHeaders } from "./k6-shared.js"
import { feedBootstrapBody } from "./rpc-contracts.js"
import {
  loginPasswordGrant,
  readAccounts,
  readOwnerTradeRows,
  readPublicProfile,
  readSessionProfile,
  scenarioDashboard,
  scenarioFeed,
  scenarioProfile,
  scenarioTrades,
} from "./read-workload-prod.js"

export { loginPasswordGrant }

export function runStagingReadPreflight(base, anonKey, session) {
  readSessionProfile(base, anonKey, session, "preflight_profile", true)
  readAccounts(base, anonKey, session, "preflight_accounts", true)
  readOwnerTradeRows(base, anonKey, session, "preflight_trades", 5, true)
}

export function scenarioMessages(base, anonKey, session) {
  const res = http.post(
    base + "/rest/v1/rpc/rpc_v2_messaging_bootstrap",
    JSON.stringify({
      p_limit: 40,
      p_cursor: null,
      p_mark_message_notifications_read: false,
    }),
    {
      headers: supabaseHeaders(anonKey, session.token, { "Content-Type": "application/json" }),
      ...httpParams("messages", { parseBody: false }),
    }
  )
  assertHttpOk(res, "messages", 200)
}

export function scenarioLeaderboard(webUrl, session) {
  const params = [
    "view=7D",
    "account=all",
    "now=" + encodeURIComponent(new Date().toISOString()),
    "viewer=" + encodeURIComponent(session.userId),
  ].join("&")
  const res = http.get(webUrl + "/api/leaderboard/trades?" + params, {
    tags: { page: "leaderboard" },
    timeout: "8s",
  })
  assertHttpOk(res, "leaderboard", 200)
}

export {
  scenarioDashboard,
  scenarioFeed,
  scenarioProfile,
  scenarioTrades,
  readPublicProfile,
}

export function scenarioFeedPage(base, anonKey, session, cursor) {
  const res = http.post(
    base + "/rest/v1/rpc/" + RPC_NAMES.feed,
    feedBootstrapBody({ cursor: cursor }),
    {
      headers: supabaseHeaders(anonKey, session.token, { "Content-Type": "application/json" }),
      ...httpParams("feed_page", { parseBody: false }),
    }
  )
  assertHttpOk(res, "feed_page", 200)
}
