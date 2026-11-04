/** Whether an account appears in dashboard/trades/calendar analytics filters. */
export function accountRowVisibleInAnalyticsFilters(row: {
  show_in_account_dropdowns?: boolean | null
}): boolean {
  return row.show_in_account_dropdowns !== false
}

/** Historical account: trades visible, no new edits on Free when true. */
export function accountRowIsViewOnly(row: {
  can_add_trades?: boolean | null
}): boolean {
  return row.can_add_trades === false
}
