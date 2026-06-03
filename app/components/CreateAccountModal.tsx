"use client"

import { useEffect, useState } from "react"

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
}

const emptyForm = {
  name: "",
  size: "",
  id: "",
  mode: "Eval",
  category: "Personal",
  consistency: "",
  maxDrawdown: "",
  dailyDrawdown: "",
  profitTarget: "",
  winningDays: "",
}

const inputClass =
  "mt-1 w-full rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-white placeholder:text-gray-500 focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

function formatNumber(value: string | number) {
  if (!value) return ""

  const num = typeof value === "number" ? value : Number(value.replace(/,/g, ""))
  if (isNaN(num)) return ""

  return num.toLocaleString("en-US")
}

function handleNumberChange(value: string, setter: (val: string) => void) {
  // remove commas
  const cleaned = value.replace(/,/g, "")

  // allow only numbers
  if (!/^\d*$/.test(cleaned)) return

  setter(cleaned)
}

export default function CreateAccountModal({
  open,
  onClose,
  onSave,
}: Props) {
  const [name, setName] = useState("")
  const [size, setSize] = useState("")
  const [id, setId] = useState("")
  const [mode, setMode] = useState("Eval")
  const [category, setCategory] = useState("Personal")
  const [consistency, setConsistency] = useState("")
  const [maxDrawdown, setMaxDrawdown] = useState("")
  const [dailyDrawdown, setDailyDrawdown] = useState("")
  const [profitTarget, setProfitTarget] = useState("")
  const [winningDays, setWinningDays] = useState("")

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

  async function handleSave() {
    const parsedData = {
      consistency: consistency ? Number(consistency) : null,
      maxDrawdown: maxDrawdown ? Number(maxDrawdown) : null,
      dailyDrawdown: dailyDrawdown ? Number(dailyDrawdown) : null,
      profitTarget: profitTarget ? Number(profitTarget) : null,
      winningDays: winningDays ? Number(winningDays) : null,
    }

    await onSave({
      name: name.trim(),
      size: size.trim(),
      id: id.trim(),
      category,
      mode: category === "Prop Firm" ? mode : null,
      rules: category === "Prop Firm" ? parsedData : null,
    })
  }

  function handleCancel() {
    resetFields()
    onClose()
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
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
            <span className="text-xs text-gray-400">Category</span>
            <select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="mt-1 w-full p-2 rounded bg-[#0f172a] border border-white/10"
            >
              <option value="Personal">Personal</option>
              <option value="Prop Firm">Prop Firm</option>
              <option value="Broker">Broker</option>
              <option value="Backtest">Backtest</option>
            </select>
          </label>

          <label className="block">
            <span className="text-xs text-gray-400">Account name</span>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className={inputClass}
              placeholder="e.g. Apex"
              autoComplete="off"
            />
          </label>

          <label className="block">
            <span className="text-xs text-gray-400">Account size</span>
            <input
              type="text"
              value={size}
              onChange={(e) => setSize(e.target.value)}
              className={inputClass}
              placeholder="e.g. 50K"
              autoComplete="off"
            />
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

          {category === "Prop Firm" && (
            <>
              <label className="block">
                <span className="text-xs text-gray-400">Mode</span>
                <select
                  value={mode}
                  onChange={(e) => setMode(e.target.value)}
                  className={inputClass}
                >
                  <option value="Eval">Eval</option>
                  <option value="Funded">Funded</option>
                </select>
              </label>

              <div className="space-y-1">
                <div className="text-xs text-gray-400">Consistency</div>
                <div className="relative w-full">
                  <input
                    type="text"
                    value={formatNumber(consistency)}
                    onChange={(e) => handleNumberChange(e.target.value, setConsistency)}
                    className="w-full pr-8 pl-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
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
                    onChange={(e) => handleNumberChange(e.target.value, setMaxDrawdown)}
                    className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
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
                    onChange={(e) => handleNumberChange(e.target.value, setDailyDrawdown)}
                    className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
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
                    onChange={(e) => handleNumberChange(e.target.value, setProfitTarget)}
                    className="w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
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
                    onChange={(e) => handleNumberChange(e.target.value, setWinningDays)}
                    className="w-full px-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none"
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
            className="rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleSave()}
            className="rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-emerald-500"
          >
            Save account
          </button>
        </div>
      </div>
    </div>
  )
}
