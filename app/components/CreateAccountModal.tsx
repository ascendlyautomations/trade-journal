"use client"

import { useEffect, useRef, useState } from "react"
import {
  ACCOUNT_SIZE_HELPER,
  ACCOUNT_SIZE_PLACEHOLDER,
  ACCOUNT_TYPES,
  accountModeOptions,
  accountNameHelperText,
  accountNamePlaceholder,
  assertRequiredAccountValue,
  defaultModeForAccountType,
  formatAccountSizeInput,
  parseAccountSizeInput,
  resolveAccountModeForSave,
  showsAccountModeSelector,
  type AccountType,
} from "@/lib/createAccountForm"
import type { TradingAccountPropFirmRules } from "@/lib/tradingAccounts"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import CustomSelect from "@/app/components/CustomSelect"
import { SELECT_MODAL_TRIGGER_CLASS } from "@/lib/accountDropdownStyles"
import { cn } from "@/app/components/ui/cn"

export type PropFirmRules = TradingAccountPropFirmRules

export type AccountFormInitialValues = {
  name: string
  size: string
  accountNumber: string
  category: AccountType
  mode: string
  rules: PropFirmRules | null
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
  /** When set, opens in edit mode with prefilled values. */
  initialAccount?: AccountFormInitialValues | null
  /** Offset below fixed navbar on mobile (onboarding setup flows). */
  belowNavbarOnMobile?: boolean
  dialogTitle?: string
  dialogSubtitle?: string
  saveLabel?: string
  /** Lock account type / mode selectors (prop firm milestone flows). */
  lockCategory?: AccountType
  lockMode?: string
  /** Override stacking when nested above another modal (default z-[100]). */
  overlayClassName?: string
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
  winningDayThreshold: "",
}

const inputClass =
  "mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

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
  initialAccount = null,
  belowNavbarOnMobile = false,
  dialogTitle,
  dialogSubtitle,
  saveLabel,
  lockCategory,
  lockMode,
  overlayClassName,
}: Props) {
  const [name, setName] = useState("")
  const [size, setSize] = useState("")
  const [id, setId] = useState("")
  const [mode, setMode] = useState("Live")
  const [category, setCategory] = useState<AccountType>("Personal")
  const [consistency, setConsistency] = useState("")
  const [consistencyMode, setConsistencyMode] = useState<"na" | "required">("na")
  const [maxDrawdown, setMaxDrawdown] = useState("")
  const [dailyDrawdown, setDailyDrawdown] = useState("")
  const [profitTarget, setProfitTarget] = useState("")
  const [winningDays, setWinningDays] = useState("")
  const [winningDaysMode, setWinningDaysMode] = useState<"na" | "required">("na")
  const [winningDayThreshold, setWinningDayThreshold] = useState("")
  const [sizeError, setSizeError] = useState<string | null>(null)
  const [isSaving, setIsSaving] = useState(false)
  const savingRef = useRef(false)
  const isEdit = Boolean(initialAccount)
  const categoryLocked = lockCategory != null
  const modeLocked = lockMode != null
  const heading =
    dialogTitle ?? (isEdit ? "Edit account" : "Create account")
  const subheading = dialogSubtitle
  const primaryLabel =
    saveLabel ?? (isEdit ? "Save changes" : "Save account")

  useEffect(() => {
    if (!open) {
      setName(emptyForm.name)
      setSize(emptyForm.size)
      setSizeError(null)
      setId(emptyForm.id)
      setMode(emptyForm.mode)
      setCategory(emptyForm.category)
      setConsistency(emptyForm.consistency)
      setConsistencyMode("na")
      setMaxDrawdown(emptyForm.maxDrawdown)
      setDailyDrawdown(emptyForm.dailyDrawdown)
      setProfitTarget(emptyForm.profitTarget)
      setWinningDays(emptyForm.winningDays)
      setWinningDaysMode("na")
      setWinningDayThreshold(emptyForm.winningDayThreshold)
      return
    }

    if (initialAccount) {
      setName(initialAccount.name)
      setSize(initialAccount.size)
      setSizeError(null)
      setId(initialAccount.accountNumber)
      setCategory(initialAccount.category)
      setMode(initialAccount.mode)
      setConsistency(
        initialAccount.rules?.consistency != null
          ? String(initialAccount.rules.consistency)
          : ""
      )
      setConsistencyMode(
        initialAccount.rules?.consistency != null ? "required" : "na"
      )
      setMaxDrawdown(
        initialAccount.rules?.maxDrawdown != null
          ? String(initialAccount.rules.maxDrawdown)
          : ""
      )
      setDailyDrawdown(
        initialAccount.rules?.dailyDrawdown != null
          ? String(initialAccount.rules.dailyDrawdown)
          : ""
      )
      setProfitTarget(
        initialAccount.rules?.profitTarget != null
          ? String(initialAccount.rules.profitTarget)
          : ""
      )
      setWinningDays(
        initialAccount.rules?.winningDays != null
          ? String(initialAccount.rules.winningDays)
          : ""
      )
      setWinningDaysMode(
        initialAccount.rules?.winningDays != null ? "required" : "na"
      )
      setWinningDayThreshold(
        initialAccount.rules?.winningDayThreshold != null
          ? String(initialAccount.rules.winningDayThreshold)
          : ""
      )
    } else {
      setName(emptyForm.name)
      setSize(emptyForm.size)
      setSizeError(null)
      setId(emptyForm.id)
      setMode(emptyForm.mode)
      setCategory(emptyForm.category)
      setConsistency(emptyForm.consistency)
      setConsistencyMode("na")
      setMaxDrawdown(emptyForm.maxDrawdown)
      setDailyDrawdown(emptyForm.dailyDrawdown)
      setProfitTarget(emptyForm.profitTarget)
      setWinningDays(emptyForm.winningDays)
      setWinningDaysMode("na")
      setWinningDayThreshold(emptyForm.winningDayThreshold)
    }
  }, [open, initialAccount])

  if (!open) return null

  function resetFields() {
    setName(emptyForm.name)
    setSize(emptyForm.size)
    setSizeError(null)
    setId(emptyForm.id)
    setMode(emptyForm.mode)
    setCategory(emptyForm.category)
    setConsistency(emptyForm.consistency)
    setConsistencyMode("na")
    setMaxDrawdown(emptyForm.maxDrawdown)
    setDailyDrawdown(emptyForm.dailyDrawdown)
    setProfitTarget(emptyForm.profitTarget)
    setWinningDays(emptyForm.winningDays)
    setWinningDaysMode("na")
    setWinningDayThreshold(emptyForm.winningDayThreshold)
  }

  function handleCategoryChange(nextCategory: AccountType) {
    setCategory(nextCategory)
    setMode(defaultModeForAccountType(nextCategory))
  }

  async function handleSave() {
    if (savingRef.current || isSaving) return
    if (!name.trim()) return

    let sizeForSave = parseAccountSizeInput(size)

    // Create only — existing accounts keep optional size on edit.
    if (!isEdit) {
      const sizeGate = assertRequiredAccountValue(size)
      if (!sizeGate.ok) {
        setSizeError(sizeGate.message)
        return
      }
      setSizeError(null)
      sizeForSave = sizeGate.value
    }

    savingRef.current = true
    setIsSaving(true)

    try {
      const winningDaysRequired = winningDaysMode === "required"
      const consistencyRequired = consistencyMode === "required"
      const parsedData = {
        consistency:
          consistencyRequired && consistency ? Number(consistency) : null,
        maxDrawdown: maxDrawdown ? Number(maxDrawdown) : null,
        dailyDrawdown: dailyDrawdown ? Number(dailyDrawdown) : null,
        profitTarget: profitTarget ? Number(profitTarget) : null,
        winningDays: winningDaysRequired && winningDays ? Number(winningDays) : null,
        winningDayThreshold:
          winningDaysRequired && winningDayThreshold
            ? Number(winningDayThreshold)
            : null,
      }

      await onSave({
        name: name.trim(),
        size: sizeForSave,
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
    <ScrollableModalShell
      open={open}
      onClose={handleCancel}
      ariaLabel={heading}
      belowNavbar={belowNavbarOnMobile}
      closeDisabled={isSaving}
      overlayClassName={cn("bg-black/60 backdrop-blur-sm", overlayClassName)}
      backdropClassName="bg-transparent"
      panelClassName="max-w-lg rounded-2xl border-white/10 bg-[#152238] sm:max-w-xl"
      headerClassName="border-white/10 px-6 pb-4 pt-6"
      bodyClassName="px-6"
      footerClassName="border-white/10 px-6 py-4"
      onOverlayClick={() => {}}
      header={
        <>
          <h2
            id="create-account-modal-title"
            className="text-lg font-semibold text-emerald-300"
          >
            {heading}
          </h2>
          {subheading ? (
            <p className="mt-1 text-sm leading-relaxed text-gray-400">
              {subheading}
            </p>
          ) : null}
        </>
      }
      footer={
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
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
            className="inline-flex items-center justify-center gap-2 rounded-xl bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-blue-500"
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
              primaryLabel
            )}
          </button>
        </div>
      }
    >
        <div className="space-y-4">
          <label className="block">
            <span className="text-xs text-gray-400">Account type</span>
            <CustomSelect
              value={category}
              disabled={categoryLocked}
              onChange={(val) => handleCategoryChange(val as AccountType)}
              triggerClassName={SELECT_MODAL_TRIGGER_CLASS}
              options={ACCOUNT_TYPES.map((type) => ({
                label: type,
                value: type,
              }))}
            />
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
            <span className="text-xs text-gray-400">Account Value</span>
            <div className="relative mt-1">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-gray-400">
                $
              </span>
              <input
                type="text"
                inputMode="numeric"
                value={formatAccountSizeInput(size)}
                onChange={(e) => {
                  handleNumberChange(e.target.value, setSize)
                  if (sizeError) setSizeError(null)
                }}
                aria-invalid={sizeError ? true : undefined}
                className={cn(
                  `${inputClass} mt-0 pl-7`,
                  sizeError && "border-red-500/70 focus:border-red-500/70"
                )}
                placeholder={ACCOUNT_SIZE_PLACEHOLDER}
                autoComplete="off"
              />
            </div>
            {sizeError ? (
              <p className="mt-1 text-xs text-red-400" role="alert">
                {sizeError}
              </p>
            ) : (
              <p className="mt-1 text-xs text-gray-500">{ACCOUNT_SIZE_HELPER}</p>
            )}
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
              <CustomSelect
                value={mode}
                disabled={modeLocked}
                onChange={setMode}
                triggerClassName={SELECT_MODAL_TRIGGER_CLASS}
                options={accountModeOptions(category)}
              />
            </label>
          ) : null}

          {category === "Prop Firm" && (
            <>
              <div className="space-y-1">
                <div className="text-xs text-gray-400">Consistency Rule</div>
                <CustomSelect
                  value={consistencyMode}
                  onChange={(val) => {
                    const next = val as "na" | "required"
                    setConsistencyMode(next)
                    if (next === "na") {
                      setConsistency("")
                    }
                  }}
                  triggerClassName={SELECT_MODAL_TRIGGER_CLASS}
                  options={[
                    { label: "Does Not Apply", value: "na" },
                    { label: "Required", value: "required" },
                  ]}
                />
              </div>

              {consistencyMode === "required" ? (
                <div className="space-y-1">
                  <div className="text-xs text-gray-400">Consistency Threshold</div>
                  <div className="relative w-full">
                    <input
                      type="text"
                      value={formatNumber(consistency)}
                      onChange={(e) =>
                        handleNumberChange(e.target.value, setConsistency)
                      }
                      className="w-full pr-8 pl-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                      placeholder="Consistency Threshold"
                    />

                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                      %
                    </span>
                  </div>
                </div>
              ) : null}

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
                <CustomSelect
                  value={winningDaysMode}
                  onChange={(val) => {
                    const next = val as "na" | "required"
                    setWinningDaysMode(next)
                    if (next === "na") {
                      setWinningDays("")
                      setWinningDayThreshold("")
                    }
                  }}
                  triggerClassName={SELECT_MODAL_TRIGGER_CLASS}
                  options={[
                    { label: "Does Not Apply", value: "na" },
                    { label: "Required", value: "required" },
                  ]}
                />
              </div>

              {winningDaysMode === "required" ? (
                <>
                  <div className="space-y-1">
                    <div className="text-xs text-gray-400">Minimum Winning Days</div>
                    <div className="relative w-full">
                      <input
                        type="text"
                        value={formatNumber(winningDays)}
                        onChange={(e) =>
                          handleNumberChange(e.target.value, setWinningDays)
                        }
                        className="w-full px-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                        placeholder="Minimum Winning Days"
                      />
                    </div>
                  </div>

                  <div className="space-y-1">
                    <div className="text-xs text-gray-400">Winning Day Threshold</div>
                    <div className="relative w-full">
                      <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm">
                        $
                      </span>

                      <input
                        type="text"
                        value={formatNumber(winningDayThreshold)}
                        onChange={(e) =>
                          handleNumberChange(e.target.value, setWinningDayThreshold)
                        }
                        className="w-full pl-8 pr-3 py-2 rounded-lg bg-[#0f172a] border border-white/10 text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"
                        placeholder="Winning Day Threshold"
                      />
                    </div>
                  </div>
                </>
              ) : null}
            </>
          )}
        </div>
    </ScrollableModalShell>
  )
}
