/** Query flag that opens the Daily Check-In form on the Dashboard. */
export const DAILY_CHECK_IN_QUERY_PARAM = "checkIn"

/** Getting Started / deep-link target — matches `?report=` Dashboard convention. */
export const DAILY_CHECK_IN_DASHBOARD_HREF = `/dashboard?${DAILY_CHECK_IN_QUERY_PARAM}=1`

export const TRADER_DAILY_CHECK_INS_TABLE = "trader_daily_check_ins" as const

export const TRADER_DAILY_CHECK_IN_CONFLICT = "user_id,check_in_date" as const

export const TRADER_DAILY_CHECK_IN_SELECT = [
  "id",
  "user_id",
  "check_in_date",
  "sleep_hours",
  "sleep_quality",
  "morning_rating",
  "stress_level",
  "energy_level",
  "focus_level",
  "notes",
  "created_at",
  "updated_at",
].join(",")
