"use client"

import {
  getTradeFormCurrencyInputDisplayValue,
  handleTradeNumericInput,
  type TradeNumericInputOptions,
} from "@/lib/formatMoney"

type TradeFormCurrencyInputProps = {
  id?: string
  value: string
  onChange: (value: string) => void
  allowNegative?: boolean
  onDecimalError?: TradeNumericInputOptions["onDecimalError"]
  tabIndex?: number
  inputClassName: string
  prefixClassName?: string
  wrapperClassName?: string
}

const DEFAULT_PREFIX_CLASS =
  "absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm"

export default function TradeFormCurrencyInput({
  id,
  value,
  onChange,
  allowNegative = false,
  onDecimalError,
  tabIndex,
  inputClassName,
  prefixClassName = DEFAULT_PREFIX_CLASS,
  wrapperClassName = "relative w-full",
}: TradeFormCurrencyInputProps) {
  return (
    <div className={wrapperClassName}>
      <span className={prefixClassName}>$</span>
      <input
        id={id}
        type="text"
        tabIndex={tabIndex}
        value={getTradeFormCurrencyInputDisplayValue(value)}
        onChange={(e) =>
          handleTradeNumericInput(e.target.value, onChange, {
            allowDecimal: true,
            allowNegative,
            onDecimalError,
          })
        }
        className={inputClassName}
      />
    </div>
  )
}
