"use client"

import { useEffect, useRef, useState } from "react"
import {
  ACCOUNT_SIZE_HELPER,
  ACCOUNT_SIZE_PLACEHOLDER,
  ACCOUNT_TYPES,
  accountModeOptions,
  accountNameHelperText,
  accountNamePlaceholder,
  defaultModeForAccountType,
  formatAccountSizeInput,
  parseAccountSizeInput,
  resolveAccountModeForSave,
  showsAccountModeSelector,
  type AccountType,
} from "@/lib/createAccountForm"

export type PropFirmRules = {
  consistency: number | null
  maxDrawdown: number | null
  dailyDrawdown: number | null
  profitTarget: number | null
  winningDays: number | null
}

export interface Props {
  open: boolean
  onClose: () => void
  onSave: (account: {
    name: string
    size: string
    id: string
    category: string
    mode: string | null
    rules: PropFirmRules | null
  }) => void | Promise<void>
  /** Offset below fixed navbar on mobile (onboarding setup flows). */
  belowNavbarOnMobile?: boolean
}

const emptyForm = {
  name: "",
  size: "",
  id: "",
  mode: "Live",
  category: "Personal" as AccountType,
  consistency: "",
  maxDrawdown: "",
  dailyDrawdown: "",
  profitTarget: "",
  winningDays: "",
}

const inputClass =
  "mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

const selectClass =
  "mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

function formatNumber(value: string | number) {
  if (!value) return ""

  const num =
    typeof value === "number" ? value : Number(value.replace(/,/g, ""))
  if (isNaN(num)) return ""

  return num.toLocaleString("en-US")
}

function handleNumberChange(value: string, setter: (val: string) => void) {
  const cleaned = value.replace(/,/g, "")
  if (!/^\d*$/.test(cleaned)) return
  setter(cleaned)
}

export default function CreateAccountModal({
  open,
  onClose,
  onSave,
  belowNavbarOnMobile = false,
}: Props) {
  const [name, setName] = useState("")
  const [size, setSize] = useState("")
  const [id, setId] = useState("")
  const [mode, setMode] = useState("Live")
  const [category, setCategory] = useState<AccountType>("Personal")
  const [consistency, setConsistency] = useState("")
  const [maxDrawdown, setMaxDrawdown] = useState("")
  const [dailyDrawdown, setDailyDrawdown] = useState("")
  const [profitTarget, setProfitTarget] = useState("")
  const [winningDays, setWinningDays] = useState("")
  const [isSaving, setIsSaving] = useState(false)
  const savingRef = useRef(false)

  useEffect(() => {
    if (!open) {
      setName(emptyForm.name)
      setSize(emptyForm.size)
      setId(emptyForm.id)
      setMode(emptyForm.mode)
      setCategory(emptyForm.category)
      setConsistency(emptyForm.consistency)
      setMaxDrawdown(emptyForm.maxDrawdown)
      setDailyDrawdown(emptyForm.dailyDrawdown)
      setProfitTarget(emptyForm.profitTarget)
      setWinningDays(emptyForm.winningDays)
    }
  }, [open])

  if (!open) return null

  function resetFields() {
    setName(emptyForm.name)
    setSize(emptyForm.size)
    setId(emptyForm.id)
    setMode(emptyForm.mode)
    setCategory(emptyForm.category)
    setConsistency(emptyForm.consistency)
    setMaxDrawdown(emptyForm.maxDrawdown)
    setDailyDrawdown(emptyForm.dailyDrawdown)
    setProfitTarget(emptyForm.profitTarget)
    setWinningDays(emptyForm.winningDays)
  }

  function handleCategoryChange(nextCategory: AccountType) {
    setCategory(nextCategory)
    setMode(defaultModeForAccountType(nextCategory))
  }

  async function handleSave() {
    if (savingRef.current || isSaving) return
    if (!name.trim()) return

    savingRef.current = true
    setIsSaving(true)

    try {
      const parsedData = {
        consistency: consistency ? Number(consistency) : null,
        maxDrawdown: maxDrawdown ? Number(maxDrawdown) : null,
        dailyDrawdown: dailyDrawdown ? Number(dailyDrawdown) : null,
        profitTarget: profitTarget ? Number(profitTarget) : null,
        winningDays: winningDays ? Number(winningDays) : null,
      }

      await onSave({
        name: name.trim(),
        size: parseAccountSizeInput(size),
        id: id.trim(),
        category,
        mode: resolveAccountModeForSave(category, mode),
        rules: category === "Prop Firm" ? parsedData : null,
      })
    } finally {
      savingRef.current = false
      setIsSaving(false)
    }
  }

  function handleCancel() {
    if (isSaving) return
    resetFields()
    onClose()
  }

  return (
    <div
      className={`fixed inset-0 z-[100] flex bg-black/60 p-4 backdrop-blur-sm ${
        belowNavbarOnMobile
          ? "items-start pt-[calc(4rem+1rem)] md:items-center md:pt-4"
          : "items-center"
      }`}
    >
      <div
        className="w-full max-w-lg sm:max-w-xl rounded-2xl border border-white/10 bg-[#152238] p-6 text-gray-100 shadow-2xl max-h-[min(90vh,720px)] overflow-y-auto"
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-account-modal-title"
      >
        <h2
          id="create-account-modal-title"
          className="text-lg font-semibold text-emerald-300"
        >
          Create account
        </h2>

        <div className="mt-5 space-y-4">
          <label className="block">
            <span className="text-xs text-gray-400">Account type</span>
            <select
              value={category}
              onChange={(e) =>
                handleCategoryChange(e.target.value as AccountType)
              }
              className={selectClass}
            >
              {ACCOUNT_TYPES.map((type) => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-xs text-gray-400">Account name</span>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className={inputClass}
              placeholder={accountNamePlaceholder(category)}
              autoComplete="off"
            />
            <p className="mt-1 text-xs text-gray-500">
              {accountNameHelperText(category)}
            </p>
          </label>

          <label className="block">
            <span className="text-xs text-gray-400">Account size</span>
            <div className="relative mt-1">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-gray-400">
                $
              </span>
              <input
                type="text"
                inputMode="numeric"
                value={formatAccountSizeInput(size)}
                onChange={(e) => handleNumberChange(e.target.value, setSize)}
                className={`${inputClass} mt-0 pl-7`}
                placeholder={ACCOUNT_SIZE_PLACEHOLDER}
                autoComplete="off"
              />
            </div>
            <p className="mt-1 text-xs text-gray-500">{ACCOUNT_SIZE_HELPER}</p>
          </label>

          <label className="block">
            <span className="text-xs text-gray-400">Account ID</span>
            <input
              type="text"
              value={id}
              onChange={(e) => setId(e.target.value)}
              className={inputClass}
              placeholder="Account number"
              autoComplete="off"
            />
          </label>

          {showsAccountModeSelector(category) ? (
            <label className="block">
              <span className="text-xs text-gray-400">Account mode</span>
              <select
                value={mode}
                onChange={(e) => setMode(e.target.value)}
                className={selectClass}
              >
                {accountModeOptions(category).map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>
          ) : null}

          {category === "Prop Firm" && (
            <>
              <div className="space-y-1">
                <div className="text-xs text-gray-400">Consistency</div>
                <div className="relative w-full">
                  <input
                    type="text"
                    value={formatNumber(consistency)}
                    onChange={(e) =>
                      handleNumberChange(e.target.value, setConsistency)
                    }
                    className="w-full pr-8 pl-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                    placeholder="Consistency"
                  />

                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    %
                  </span>
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-gray-400">Max Drawdown</div>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    value={formatNumber(maxDrawdown)}
                    onChange={(e) =>
                      handleNumberChange(e.target.value, setMaxDrawdown)
                    }
                    className="w-full pl-8 pr-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                    placeholder="Max Drawdown"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-gray-400">Daily Drawdown</div>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    value={formatNumber(dailyDrawdown)}
                    onChange={(e) =>
                      handleNumberChange(e.target.value, setDailyDrawdown)
                    }
                    className="w-full pl-8 pr-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                    placeholder="Daily Drawdown"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-gray-400">Profit Target</div>
                <div className="relative w-full">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                    $
                  </span>

                  <input
                    type="text"
                    value={formatNumber(profitTarget)}
                    onChange={(e) =>
                      handleNumberChange(e.target.value, setProfitTarget)
                    }
                    className="w-full pl-8 pr-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                    placeholder="Profit Target"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <div className="text-xs text-gray-400">Winning Days</div>
                <div className="relative w-full">
                  <input
                    type="text"
                    value={formatNumber(winningDays)}
                    onChange={(e) =>
                      handleNumberChange(e.target.value, setWinningDays)
                    }
                    className="w-full px-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                    placeholder="Winning Days"
                  />
                </div>
              </div>
            </>
          )}
        </div>

        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            onClick={handleCancel}
            disabled={isSaving}
            className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleSave()}
            disabled={isSaving || !name.trim()}
            className="inline-flex items-center justify-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSaving ? (
              <>
                <span
                  className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-white border-t-transparent"
                  aria-hidden
                />
                Saving…
              </>
            ) : (
              "Save account"
            )}
          </button>
        </div>
      </div>
    </div>
  )
}
