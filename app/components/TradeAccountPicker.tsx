"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import {
  navigateToManageAccounts,
} from "./TradeFilterBar"
import {
  formatAccountNameWithSizeDisplay,
  safeAccountNumberLabel,
} from "@/lib/tradeAccountDisplay"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import {
  copyGroupFilterValue,
  findCopyGroupByFilterValue,
  findCopyGroupById,
  isCopyGroupFilterValue,
  MANAGE_COPY_GROUPS_SETTINGS_HREF,
} from "@/lib/tradeAccountSelection"
import {
  ACCOUNT_DROPDOWN_ACTION_CLASS,
  ACCOUNT_DROPDOWN_DIVIDER_CLASS,
  ACCOUNT_DROPDOWN_FILTER_TRIGGER_CLASS,
  ACCOUNT_DROPDOWN_FILTER_WRAPPER_CLASS,
  ACCOUNT_DROPDOWN_ITEM_CLASS,
  ACCOUNT_DROPDOWN_MANAGE_CLASS,
  ACCOUNT_DROPDOWN_PANEL_CLASS,
  ACCOUNT_DROPDOWN_ROW_TEXT_CLASS,
  ACCOUNT_DROPDOWN_SUBMISSION_WRAPPER_CLASS,
  ACCOUNT_DROPDOWN_TRIGGER_CLASS,
} from "@/lib/accountDropdownStyles"
import { cn } from "@/app/components/ui/cn"

/** Mirrors `InputTradeForm` account row shape after `accounts` fetch. */
export type TradeAccountOption = {
  name: string
  size: string
  id: string
  account_number?: string | null
  mode: string | null
  category?: string | null
}

type FilterOption = {
  value: string
  label: string
}

type MenuView = "accounts" | "copy-groups"

function accountNumberSuffix(acc: {
  account_number?: string | null
}): string {
  const num = safeAccountNumberLabel(acc.account_number)
  return num ? ` • #${num}` : ""
}

function formatMode(mode: unknown) {
  if (!mode) return "Live"
  const m = String(mode).toLowerCase()
  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"
  if (m === "sim") return "Sim"
  if (m === "backtest") return "Backtest"
  return String(mode)
}

function formatAccountLine(acc: TradeAccountOption): string {
  return `${formatAccountNameWithSizeDisplay(acc.name, acc.size)} • ${acc.category || "Personal"} • ${formatMode(acc.mode)}${accountNumberSuffix(acc)}`
}

type TradeAccountPickerProps = {
  accounts: TradeAccountOption[]
  className?: string
  triggerId?: string
  triggerClassName?: string
  /** Enables Copy Trading navigation when true. */
  isPro?: boolean
  copyGroups?: CopyTradingGroup[]
  /** Submission mode */
  selectedAccount?: TradeAccountOption | null
  selectedCopyGroupId?: string | null
  onSelect?: (acc: TradeAccountOption | null) => void
  onSelectCopyGroup?: (groupId: string | null) => void
  onOpenCreate?: () => void
  disableCreate?: boolean
  showExternalCreateButton?: boolean
  hideManageAccounts?: boolean
  /** Filter mode (dashboard / trades) */
  filterValue?: string
  filterOptions?: FilterOption[]
  onFilterChange?: (value: string) => void
  filterPlaceholder?: string
}

function RowText({ children }: { children: React.ReactNode }) {
  return <span className={ACCOUNT_DROPDOWN_ROW_TEXT_CLASS}>{children}</span>
}

function ManageRow({
  children,
  onClick,
}: {
  children: React.ReactNode
  onClick: () => void
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onClick()
        }
      }}
      className={ACCOUNT_DROPDOWN_MANAGE_CLASS}
    >
      <RowText>{children}</RowText>
    </div>
  )
}

function ActionRow({
  children,
  onClick,
}: {
  children: React.ReactNode
  onClick: () => void
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onClick()
        }
      }}
      className={ACCOUNT_DROPDOWN_ACTION_CLASS}
    >
      <RowText>{children}</RowText>
    </div>
  )
}

function ItemRow({
  children,
  onClick,
  className,
}: {
  children: React.ReactNode
  onClick: () => void
  className?: string
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onClick()
        }
      }}
      className={className ?? ACCOUNT_DROPDOWN_ITEM_CLASS}
    >
      <RowText>{children}</RowText>
    </div>
  )
}

export default function TradeAccountPicker({
  accounts,
  className = "",
  triggerId,
  triggerClassName,
  isPro = false,
  copyGroups = [],
  selectedAccount = null,
  selectedCopyGroupId = null,
  onSelect,
  onSelectCopyGroup,
  onOpenCreate,
  disableCreate = false,
  showExternalCreateButton = true,
  hideManageAccounts = false,
  filterValue,
  filterOptions = [],
  onFilterChange,
  filterPlaceholder = "All Accounts",
}: TradeAccountPickerProps) {
  const router = useRouter()
  const isFilterMode = onFilterChange != null
  const showCopyTrading = isPro
  const resolvedTriggerClassName =
    triggerClassName ??
    (isFilterMode
      ? ACCOUNT_DROPDOWN_FILTER_TRIGGER_CLASS
      : ACCOUNT_DROPDOWN_TRIGGER_CLASS)

  const [open, setOpen] = useState(false)
  const [menuView, setMenuView] = useState<MenuView>("accounts")

  const selectedCopyGroup = useMemo(
    () =>
      isFilterMode
        ? findCopyGroupByFilterValue(filterValue, copyGroups)
        : findCopyGroupById(selectedCopyGroupId, copyGroups),
    [copyGroups, filterValue, isFilterMode, selectedCopyGroupId]
  )

  const triggerLabel = useMemo(() => {
    if (isFilterMode) {
      if (!filterValue || filterValue === "all") return filterPlaceholder
      if (selectedCopyGroup) return selectedCopyGroup.name
      const option = filterOptions.find((opt) => opt.value === filterValue)
      return option?.label ?? filterPlaceholder
    }

    if (selectedCopyGroup) return selectedCopyGroup.name
    if (selectedAccount) return formatAccountLine(selectedAccount)
    return "Select Account"
  }, [
    filterOptions,
    filterPlaceholder,
    filterValue,
    isFilterMode,
    selectedAccount,
    selectedCopyGroup,
  ])

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      const target = e.target as HTMLElement
      if (!target.closest(".trade-account-picker")) {
        setOpen(false)
      }
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [])

  useEffect(() => {
    if (!open) {
      setMenuView("accounts")
    }
  }, [open])

  function closeMenu() {
    setOpen(false)
    setMenuView("accounts")
  }

  function handleManageAccounts() {
    navigateToManageAccounts(router)
    closeMenu()
  }

  function handleManageCopyGroups() {
    router.push(MANAGE_COPY_GROUPS_SETTINGS_HREF)
    closeMenu()
  }

  function handleSelectAccount(acc: TradeAccountOption) {
    if (isFilterMode) {
      onFilterChange?.(
        filterOptions.find((opt) => opt.value.includes(`|${acc.id}`))?.value ??
          acc.id
      )
    } else {
      onSelectCopyGroup?.(null)
      onSelect?.(acc)
    }
    closeMenu()
  }

  function handleSelectFilterOption(value: string) {
    onFilterChange?.(value)
    closeMenu()
  }

  function handleSelectCopyGroup(group: CopyTradingGroup) {
    if (isFilterMode) {
      onFilterChange?.(copyGroupFilterValue(group.id))
    } else {
      onSelect?.(null)
      onSelectCopyGroup?.(group.id)
    }
    closeMenu()
  }

  const accountRows = isFilterMode
    ? filterOptions.map((opt) => ({
        key: opt.value,
        label: opt.label,
        onClick: () => handleSelectFilterOption(opt.value),
      }))
    : accounts.map((acc) => ({
        key: String(acc.id),
        label: formatAccountLine(acc),
        onClick: () => handleSelectAccount(acc),
      }))

  const accountsPanel = (
    <>
      {isFilterMode ? (
        <ItemRow onClick={() => handleSelectFilterOption("all")}>
          {filterPlaceholder}
        </ItemRow>
      ) : null}

      {showCopyTrading ? (
        <ActionRow onClick={() => setMenuView("copy-groups")}>
          Copy Trading
        </ActionRow>
      ) : null}

      {(isFilterMode || showCopyTrading) && accountRows.length > 0 ? (
        <div className={ACCOUNT_DROPDOWN_DIVIDER_CLASS} aria-hidden="true">
          <span className="md:hidden">────────</span>
          <span className="hidden md:inline">────────────────────</span>
        </div>
      ) : null}

      <div className="max-h-48 overflow-y-auto overscroll-contain">
        {accountRows.map((row) => (
          <ItemRow key={row.key} onClick={row.onClick}>
            {row.label}
          </ItemRow>
        ))}
      </div>

      {!hideManageAccounts ? (
        <>
          <div className={ACCOUNT_DROPDOWN_DIVIDER_CLASS} aria-hidden="true">
            <span className="md:hidden">────────</span>
            <span className="hidden md:inline">────────────────────</span>
          </div>
          <ManageRow onClick={handleManageAccounts}>
            ⚙️ Manage Accounts
          </ManageRow>
        </>
      ) : null}

      {!isFilterMode && onOpenCreate ? (
        !disableCreate ? (
          <ItemRow
            onClick={() => {
              onOpenCreate()
              closeMenu()
            }}
            className="cursor-pointer px-3 py-2 text-sm text-green-400 hover:bg-[#1f2937]"
          >
            <RowText>➕ Add Account</RowText>
          </ItemRow>
        ) : (
          <div className="px-3 py-2 text-sm text-amber-300/90">
            Upgrade to Pro to add more accounts
          </div>
        )
      ) : null}
    </>
  )

  const copyGroupsPanel = (
    <>
      <ItemRow onClick={() => setMenuView("accounts")}>
        ← Single Accounts
      </ItemRow>

      <div className={ACCOUNT_DROPDOWN_DIVIDER_CLASS} aria-hidden="true">
        <span className="md:hidden">────────</span>
        <span className="hidden md:inline">────────────────────</span>
      </div>

      <div className="max-h-48 overflow-y-auto overscroll-contain">
        {copyGroups.length === 0 ? (
          <div className="px-3 py-2 text-sm text-gray-500">
            No copy trading groups yet.
          </div>
        ) : (
          copyGroups.map((group) => (
            <ItemRow
              key={group.id}
              onClick={() => handleSelectCopyGroup(group)}
            >
              {group.name}
            </ItemRow>
          ))
        )}
      </div>

      <div className={ACCOUNT_DROPDOWN_DIVIDER_CLASS} aria-hidden="true">
        <span className="md:hidden">────────</span>
        <span className="hidden md:inline">────────────────────</span>
      </div>
      <ManageRow onClick={handleManageCopyGroups}>
        ⚙️ Manage Copy Trading Groups
      </ManageRow>
    </>
  )

  return (
    <div
      className={cn(
        isFilterMode
          ? ACCOUNT_DROPDOWN_FILTER_WRAPPER_CLASS
          : "flex min-w-0 flex-col gap-2 sm:flex-row sm:items-stretch",
        !isFilterMode && ACCOUNT_DROPDOWN_SUBMISSION_WRAPPER_CLASS,
        className
      )}
    >
      <div
        className={cn(
          "relative w-full min-w-0 trade-account-picker",
          !isFilterMode && "flex-1 md:flex-none"
        )}
      >
        <button
          id={triggerId}
          type="button"
          onClick={() => setOpen((prev) => !prev)}
          className={resolvedTriggerClassName}
        >
          <span className={cn(ACCOUNT_DROPDOWN_ROW_TEXT_CLASS, "text-left")}>
            {triggerLabel}
          </span>
          <span className="shrink-0 text-gray-400">▾</span>
        </button>

        {open ? (
          <div className={cn(ACCOUNT_DROPDOWN_PANEL_CLASS, "overflow-hidden p-0")}>
            {showCopyTrading ? (
              <div className="relative overflow-hidden">
                <div
                  className={cn(
                    "flex w-[200%] transition-transform duration-200 ease-out",
                    menuView === "copy-groups" ? "-translate-x-1/2" : "translate-x-0"
                  )}
                >
                  <div className="w-1/2 shrink-0">{accountsPanel}</div>
                  <div className="w-1/2 shrink-0">{copyGroupsPanel}</div>
                </div>
              </div>
            ) : (
              accountsPanel
            )}
          </div>
        ) : null}
      </div>

      {!isFilterMode && showExternalCreateButton && onOpenCreate ? (
        <button
          type="button"
          onClick={onOpenCreate}
          disabled={disableCreate}
          className="shrink-0 rounded-lg border border-emerald-500/40 bg-emerald-500/15 px-4 py-2.5 text-sm font-medium text-emerald-200 transition hover:bg-emerald-500/25 disabled:cursor-not-allowed whitespace-normal text-center sm:whitespace-nowrap"
        >
          {disableCreate ? "Upgrade to Pro to add more accounts" : "+ Create Account"}
        </button>
      ) : null}
    </div>
  )
}

export {
  copyGroupFilterValue,
  isCopyGroupFilterValue,
  MANAGE_COPY_GROUPS_SETTINGS_HREF,
}
