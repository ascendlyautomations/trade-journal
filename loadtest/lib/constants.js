/**
 * Load-test projections — keep in sync with app sources (see loadtestInfrastructure.contract.test.ts).
 * @see lib/appDataCache.ts ACCOUNTS_SELECT
 * @see lib/publicAccountPrivacy.ts TRADES_ANALYTICS_FIELDS (owner reads use rpc_v1_trades_owner_rows, not REST)
 */

export const ACCOUNTS_SELECT =
  "id,account_number,name,account_size,mode,category,is_active,can_add_trades,show_in_account_dropdowns,note,consistency,max_drawdown,drawdown_type,daily_drawdown,profit_target,winning_days,winning_day_threshold"

export const SESSION_PROFILE_SELECT =
  "id,name,username,onboarding_completed,is_pro,avatar_url"

export const PUBLIC_PROFILE_SELECT =
  "id,username,name,bio,avatar_url,trading_style,trader_type,primary_market,started_trading,is_private,created_at"

/** Public profile trade cards — columns granted on public.trades for authenticated. */
export const PROFILE_PUBLIC_TRADES_SELECT =
  "id,created_at,pnl,rr,mode,account_type"

export const REQUEST_TIMEOUT = "8s"

export const PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"
export const STAGING_PROJECT_REF = "hxlcvffvyadlxcsqxxoy"

export const RPC_NAMES = {
  feed: "rpc_v1_feed_bootstrap",
  dashboard: "rpc_v1_dashboard_bootstrap",
  calendar: "rpc_v1_calendar_bootstrap",
  tradesOwnerRows: "rpc_v1_trades_owner_rows",
  session: "rpc_v1_session_bootstrap",
}

export const DASHBOARD_TRADE_LIMIT_APP = 500
export const DASHBOARD_RPC_TRADE_LIMIT = 120
export const PREFLIGHT_DASHBOARD_TRADE_LIMIT = 20
export const DASHBOARD_OWNER_ROWS_WINDOW = 120
export const DASHBOARD_OWNER_ROWS_HISTORY = 500
export const TRADES_PAGE_OWNER_ROWS_LIMIT = 200
export const PREFLIGHT_OWNER_ROWS_LIMIT = 5
export const FEED_PAGE_LIMIT = 8
