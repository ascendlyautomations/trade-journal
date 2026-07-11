"use client"

import { useEffect, useMemo, useState } from "react"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import { cn } from "@/app/components/ui/cn"
import type { CopyTradingGroup } from "@/lib/copyTradingGroups"
import {
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"
import { formatTradingAccountSelectorLabel } from "@/lib/tradeAccountDisplay"

type CopyTradingGroupEditorModalProps = {
  open: boolean
  accounts: TradingAccountListItem[]
  editingGroup: CopyTradingGroup | null
  saving?: boolean
  onClose: () => void
  onSave: (payload: { name: string; accountIds: string[] }) => void
}

const inputClass =
  "mt-1.5 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

export default function CopyTradingGroupEditorModal({
  open,
  accounts,
  editingGroup,
  saving = false,
  onClose,
  onSave,
}: CopyTradingGroupEditorModalProps) {
  const [name, setName] = useState("")
  const [selectedIds, setSelectedIds] = useState<string[]>([])

  const isEdit = Boolean(editingGroup)

  useEffect(() => {
    if (!open) return
    setName(editingGroup?.name ?? "")
    setSelectedIds(editingGroup?.accountIds ?? [])
  }, [open, editingGroup])

  const selectableAccounts = useMemo(
    () =>
      [...accounts].sort((a, b) =>
        a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
      ),
    [accounts]
  )

  function toggleAccount(accountId: string) {
    setSelectedIds((prev) =>
      prev.includes(accountId)
        ? prev.filter((id) => id !== accountId)
        : [...prev, accountId]
    )
  }

  function handleCancel() {
    if (saving) return
    onClose()
  }

  function handleSubmit() {
    onSave({ name: name.trim(), accountIds: selectedIds })
  }

  if (!open) return null

  return (
    <ScrollableModalShell
      open={open}
      onClose={handleCancel}
      ariaLabel={isEdit ? "Edit copy trading group" : "Create copy trading group"}
      closeDisabled={saving}
      overlayClassName="bg-black/60 backdrop-blur-sm"
      backdropClassName="bg-transparent"
      panelClassName="max-w-lg rounded-2xl border-white/10 bg-[#152238] sm:max-w-xl"
      headerClassName="border-white/10 px-6 pb-4 pt-6"
      bodyClassName="flex min-h-0 flex-1 flex-col overflow-hidden px-6"
      footerClassName="border-white/10 px-6 py-4"
      onOverlayClick={() => {}}
      header={
        <>
          <h2 className="text-lg font-semibold text-emerald-300">Copy Trading Group</h2>
          <p className="mt-1 text-sm leading-relaxed text-gray-400">
            Automatically journal the same trade across multiple linked trading
            accounts.
          </p>
        </>
      }
      footer={
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={handleCancel}
            disabled={saving}
            className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={saving || !name.trim() || selectedIds.length === 0}
            className="inline-flex items-center justify-center gap-2 rounded-xl bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
          >
            {saving ? (
              <>
                <span
                  className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent"
                  aria-hidden
                />
                Saving…
              </>
            ) : isEdit ? (
              "Save Changes"
            ) : (
              "Create Group"
            )}
          </button>
        </div>
      }
    >
      <label className="block shrink-0">
        <span className="text-sm font-medium text-gray-200">Group name</span>
        <input
          type="text"
          value={name}
          disabled={saving}
          onChange={(e) => setName(e.target.value)}
          placeholder="Apex Accounts"
          className={inputClass}
        />
      </label>

      <div className="mt-5 flex min-h-0 flex-1 flex-col pb-2">
        <p className="shrink-0 text-sm font-medium text-gray-200">Trading accounts</p>
        {selectableAccounts.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">
            Create trading accounts first, then link them to a copy group.
          </p>
        ) : (
          <ul
            className="mt-2 min-h-0 max-h-[min(40dvh,320px)] flex-1 space-y-2 overflow-y-auto overscroll-contain rounded-xl border border-white/10 bg-black/20 p-2 sm:p-3"
            aria-label="Select trading accounts"
          >
            {selectableAccounts.map((account) => {
              const checked = selectedIds.includes(account.id)
              const isActive = account.is_active !== false
              const selectorLabel = formatTradingAccountSelectorLabel({
                name: account.name,
                size: account.size,
                account_number: account.account_number,
                mode: account.mode,
              })

              return (
                <li key={account.id}>
                  <label
                    className={cn(
                      "flex cursor-pointer items-start gap-3 rounded-xl border p-3 transition",
                      checked
                        ? "border-blue-400/40 bg-blue-500/10"
                        : "border-white/10 bg-white/[0.03] hover:bg-white/[0.06]"
                    )}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={saving}
                      onChange={() => toggleAccount(account.id)}
                      className="mt-1 accent-blue-500"
                      aria-label={`Include ${selectorLabel}`}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block text-sm font-medium text-white">
                        {selectorLabel}
                      </span>
                      <span
                        className={cn(
                          "mt-1 block text-xs",
                          isActive ? "text-emerald-300" : "text-red-300/90"
                        )}
                      >
                        {isActive ? "Active" : "Inactive"}
                      </span>
                    </span>
                  </label>
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </ScrollableModalShell>
  )
}
