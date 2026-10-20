import { SELECT_MENU_CLASS } from "@/lib/accountDropdownStyles"

/** Shared Backtest Lab filter control classes (paired with backtestLabTheme.css). */

export const BACKTEST_LAB_FILTER_CONTROL_CLASS = "backtest-lab-filter-control"

export const BACKTEST_LAB_FILTER_LABEL_TRUNCATE_CLASS =
  "min-w-0 flex-1 truncate text-left"

export const BACKTEST_LAB_DATE_FIELD_CLASS =
  "backtest-lab-date-field tt-date-field--compact w-full min-w-0 border-0 bg-transparent p-0 shadow-none"

export const BACKTEST_LAB_SELECT_TRIGGER_CLASS = `${BACKTEST_LAB_FILTER_CONTROL_CLASS} flex min-w-0 cursor-pointer items-center justify-between`

export const BACKTEST_LAB_SELECT_MENU_CLASS = `backtest-lab-select-menu ${SELECT_MENU_CLASS}`

export const BACKTEST_LAB_SELECT_PROPS = {
  className: "w-full min-w-0",
  triggerClassName: BACKTEST_LAB_SELECT_TRIGGER_CLASS,
  triggerLabelClassName: BACKTEST_LAB_FILTER_LABEL_TRUNCATE_CLASS,
  menuClassName: BACKTEST_LAB_SELECT_MENU_CLASS,
} as const
