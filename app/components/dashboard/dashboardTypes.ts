import type { AccountRowForDisplay } from "@/lib/tradeAccountDisplay"

export type DashboardAccountRow = AccountRowForDisplay & {
  category?: string | null
  [key: string]: unknown
}

export type DashboardTradeRow = {
  id?: string | number | null
  account_id?: string | null
  account_type?: string | null
  account_name?: string | null
  account_number?: string | null
  account_size?: string | null
  created_at?: string | null
  direction?: string | null
  entry_time?: string | null
  exit_time?: string | null
  is_public?: boolean | null
  mode?: string | null
  pnl?: number | null
  public_description?: string | null
  rr?: unknown
  session?: string | null
  strategy?: string | null
  ticker?: string | null
  [key: string]: unknown
}
