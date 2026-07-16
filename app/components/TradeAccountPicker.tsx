"use client"

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { createPortal } from "react-dom"
import { useRouter } from "next/navigation"
import {
  navigateToManageAccounts,
} from "./TradeFilterBar"
import {
  formatTradingAccountSelectorParts,
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
  ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS,
  ACCOUNT_DROPDOWN_ROW_TEXT_CLASS,
  ACCOUNT_DROPDOWN_SUBMISSION_WRAPPER_CLASS,
  ACCOUNT_DROPDOWN_TRIGGER_CLASS,
} from "@/lib/accountDropdownStyles"
import { cn } from "@/app/components/ui/cn"

type MenuPosition = {
  top: number
  left: number
  width: number
}

/** Mirrors `InputTradeForm` account row shape after `accounts` fetch. */
export type TradeAccountOption = {
  name: string
  size: string
  id: string
  account_number?: string | null
  mode: string | null
  category?: string | null
  /** Prop Firm rule fields — optional; used by Passed Eval continuance. */
  consistency?: number | string | null
  max_drawdown?: number | string | null
  daily_drawdown?: number | string | null
  profit_target?: number | string | null
  winning_days?: number | string | null
  winning_day_threshold?: number | string | null
}

type FilterOption = {
  value: string
  label: string
  labelName?: string
  labelSuffix?: string
}

type MenuView = "accounts" | "copy-groups"

function AccountSelectorLabelText({
  name,
  suffix,
  className,
}: {
  name: string
  suffix: string
  className?: string
}) {
  return (
    <span className={cn("flex min-w-0 flex-1 items-center", className)}>
      <span className="min-w-0 truncate">{name}</span>
      {suffix ? <span className="shrink-0">{suffix}</span> : null}
    </span>
  )
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
  const content =
    typeof children === "string" || typeof children === "number" ? (
      <RowText>{children}</RowText>
    ) : (
      children
    )
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
      {content}
    </div>
  )
}

/** Collapsed account list shows this many rows before "View More Accounts". */
const ACCOUNT_LIST_COLLAPSED_LIMIT = 5

function DropdownDivider() {
  return (
    <div className={ACCOUNT_DROPDOWN_DIVIDER_CLASS} aria-hidden="true">
      <span className="md:hidden">────────</span>
      <span className="hidden md:inline">────────────────────</span>
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
  const [accountsExpanded, setAccountsExpanded] = useState(false)
  const [menuPosition, setMenuPosition] = useState<MenuPosition | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  function updateMenuPosition() {
    const trigger = triggerRef.current
    if (!trigger) return
    const rect = trigger.getBoundingClientRect()
    const viewportPad = 8
    setMenuPosition({
      top: rect.bottom + 4,
      left: Math.min(
        rect.left,
        Math.max(viewportPad, window.innerWidth - rect.width - viewportPad)
      ),
      width: rect.width,
    })
  }

  const selectedCopyGroup = useMemo(
    () =>
      isFilterMode
        ? findCopyGroupByFilterValue(filterValue, copyGroups)
        : findCopyGroupById(selectedCopyGroupId, copyGroups),
    [copyGroups, filterValue, isFilterMode, selectedCopyGroupId]
  )

  const selectedAccountParts = useMemo(() => {
    if (!selectedAccount) return null
    return formatTradingAccountSelectorParts({
      name: selectedAccount.name,
      size: selectedAccount.size,
      account_number: selectedAccount.account_number,
      mode: selectedAccount.mode,
    })
  }, [selectedAccount])

  const triggerLabel = useMemo(() => {
    if (isFilterMode) {
      if (!filterValue || filterValue === "all") {
        return { kind: "text" as const, text: filterPlaceholder }
      }
      if (selectedCopyGroup) {
        return { kind: "text" as const, text: selectedCopyGroup.name }
      }
      const option = filterOptions.find((opt) => opt.value === filterValue)
      if (option?.labelName != null) {
        return {
          kind: "parts" as const,
          name: option.labelName,
          suffix: option.labelSuffix ?? "",
        }
      }
      return {
        kind: "text" as const,
        text: option?.label ?? filterPlaceholder,
      }
    }

    if (selectedCopyGroup) {
      return { kind: "text" as const, text: selectedCopyGroup.name }
    }
    if (selectedAccountParts) {
      return {
        kind: "parts" as const,
        name: selectedAccountParts.name,
        suffix: selectedAccountParts.suffix,
      }
    }
    return { kind: "text" as const, text: "Select Account" }
  }, [
    filterOptions,
    filterPlaceholder,
    filterValue,
    isFilterMode,
    selectedAccountParts,
    selectedCopyGroup,
  ])

  useLayoutEffect(() => {
    if (!open) {
      setMenuPosition(null)
      return
    }
    updateMenuPosition()
    window.addEventListener("resize", updateMenuPosition)
    window.addEventListener("scroll", updateMenuPosition, true)
    return () => {
      window.removeEventListener("resize", updateMenuPosition)
      window.removeEventListener("scroll", updateMenuPosition, true)
    }
  }, [open, menuView, accountsExpanded])

  useEffect(() => {
    if (!open) return
    function handleClickOutside(e: MouseEvent) {
      const target = e.target as Node
      if (rootRef.current?.contains(target)) return
      if (menuRef.current?.contains(target)) return
      setOpen(false)
    }
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false)
    }
    document.addEventListener("mousedown", handleClickOutside)
    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("mousedown", handleClickOutside)
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open])

  useEffect(() => {
    if (!open) {
      setMenuView("accounts")
      setAccountsExpanded(false)
    }
  }, [open])

  function closeMenu() {
    setOpen(false)
    setMenuView("accounts")
    setAccountsExpanded(false)
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
        labelName: opt.labelName ?? opt.label,
        labelSuffix: opt.labelSuffix ?? "",
        onClick: () => handleSelectFilterOption(opt.value),
      }))
    : accounts.map((acc) => {
        const parts = formatTradingAccountSelectorParts({
          name: acc.name,
          size: acc.size,
          account_number: acc.account_number,
          mode: acc.mode,
        })
        return {
          key: String(acc.id),
          labelName: parts.name,
          labelSuffix: parts.suffix,
          onClick: () => handleSelectAccount(acc),
        }
      })

  const showViewMoreAccounts =
    !accountsExpanded && accountRows.length > ACCOUNT_LIST_COLLAPSED_LIMIT
  const visibleAccountRows =
    showViewMoreAccounts
      ? accountRows.slice(0, ACCOUNT_LIST_COLLAPSED_LIMIT)
      : accountRows
  const accountListNeedsScroll =
    accountsExpanded && accountRows.length > ACCOUNT_LIST_COLLAPSED_LIMIT

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
        <DropdownDivider />
      ) : null}

      <div
        className={cn(
          accountListNeedsScroll &&
            "max-h-60 overflow-y-auto overscroll-contain"
        )}
      >
        {visibleAccountRows.map((row) => (
          <ItemRow key={row.key} onClick={row.onClick}>
            <AccountSelectorLabelText
              name={row.labelName}
              suffix={row.labelSuffix}
            />
          </ItemRow>
        ))}
        {showViewMoreAccounts ? (
          <ActionRow onClick={() => setAccountsExpanded(true)}>
            View More Accounts
          </ActionRow>
        ) : null}
      </div>

      {!hideManageAccounts || (!isFilterMode && onOpenCreate) ? (
        <DropdownDivider />
      ) : null}

      {!hideManageAccounts ? (
        <ManageRow onClick={handleManageAccounts}>
          ⚙️ Manage Accounts
        </ManageRow>
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

      <DropdownDivider />

      <div className="max-h-60 overflow-y-auto overscroll-contain">
        {copyGroups.length === 0 ? (
          <div className="px-3 py-2 text-sm text-gray-400">
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

      <DropdownDivider />
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
        ref={rootRef}
        className={cn(
          "relative w-full min-w-0 trade-account-picker",
          !isFilterMode && "flex-1 md:flex-none"
        )}
      >
        <button
          ref={triggerRef}
          id={triggerId}
          type="button"
          aria-haspopup="listbox"
          aria-expanded={open}
          onClick={() => setOpen((prev) => !prev)}
          className={resolvedTriggerClassName}
        >
          <span className="flex min-w-0 flex-1 items-center text-left">
            {triggerLabel.kind === "parts" ? (
              <AccountSelectorLabelText
                name={triggerLabel.name}
                suffix={triggerLabel.suffix}
              />
            ) : (
              <span className={cn(ACCOUNT_DROPDOWN_ROW_TEXT_CLASS, "text-left")}>
                {triggerLabel.text}
              </span>
            )}
          </span>
          <span className="shrink-0 text-gray-400" aria-hidden="true">
            ▾
          </span>
        </button>

        {open && menuPosition
          ? createPortal(
              <div
                ref={menuRef}
                className={cn(
                  ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS,
                  // Pin footer actions (Add Account) — do not clip the whole panel.
                  "max-h-none overflow-hidden p-0 max-md:w-max max-md:min-w-full max-md:max-w-[calc(100vw-1.5rem)]"
                )}
                style={{
                  top: menuPosition.top,
                  left: menuPosition.left,
                  width: menuPosition.width,
                }}
              >
                {showCopyTrading ? (
                  <div className="relative overflow-hidden">
                    <div
                      className={cn(
                        "flex w-[200%] transition-transform duration-200 ease-out",
                        menuView === "copy-groups"
                          ? "-translate-x-1/2"
                          : "translate-x-0"
                      )}
                    >
                      <div className="w-1/2 shrink-0">{accountsPanel}</div>
                      <div className="w-1/2 shrink-0">{copyGroupsPanel}</div>
                    </div>
                  </div>
                ) : (
                  accountsPanel
                )}
              </div>,
              document.body
            )
          : null}
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
