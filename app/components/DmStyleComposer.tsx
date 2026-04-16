"use client"

import type { ChangeEvent, ReactNode, RefObject } from "react"

export type DmStyleComposerProps = {
  value: string
  onChange: (value: string) => void
  onSend: () => void
  placeholder?: string
  textDisabled?: boolean
  sendDisabled?: boolean
  onImageChange: (e: ChangeEvent<HTMLInputElement>) => void
  imageDisabled?: boolean
  onTradeClick?: () => void
  tradeDisabled?: boolean
  /** Shown above the input row (e.g. typing indicator) */
  beforeRow?: ReactNode
  /** Shown below the input row (e.g. “Seen”, file name) */
  afterRow?: ReactNode
  /** Optional ref on the hidden file input (Messages clears this after send) */
  fileInputRef?: RefObject<HTMLInputElement | null>
}

/**
 * Shared bottom composer matching the Messages / DM mobile layout:
 * text input + 📷 + optional 📊 + Send — same spacing and control sizing.
 */
export default function DmStyleComposer({
  value,
  onChange,
  onSend,
  placeholder = "Send message...",
  textDisabled = false,
  sendDisabled = false,
  onImageChange,
  imageDisabled = false,
  onTradeClick,
  tradeDisabled = false,
  beforeRow,
  afterRow,
  fileInputRef,
}: DmStyleComposerProps) {
  return (
    <div className="mt-auto shrink-0 border-t border-white/10 bg-[#0B1220] p-2 md:bg-[#020617] md:p-4">
      {beforeRow ? <div className="mb-1">{beforeRow}</div> : null}
      <div className="flex w-full items-center gap-1">
        <input
          type="text"
          placeholder={placeholder}
          value={value}
          disabled={textDisabled}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault()
              if (!sendDisabled) onSend()
            }
          }}
          className="flex-1 rounded bg-[#111827] px-3 py-2 text-sm text-white placeholder:text-gray-500 disabled:opacity-60"
        />
        <label className="flex shrink-0 cursor-pointer items-center justify-center rounded bg-[#1f2937] p-2 md:hover:bg-[#334155]">
          <span aria-hidden>📷</span>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            className="hidden"
            disabled={imageDisabled}
            onChange={onImageChange}
          />
        </label>
        {onTradeClick ? (
          <button
            type="button"
            onClick={onTradeClick}
            disabled={tradeDisabled}
            aria-label="Send a trade"
            title="Send a trade"
            className="flex shrink-0 items-center justify-center rounded bg-[#1f2937] p-2 md:hover:bg-[#334155] disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span aria-hidden>📊</span>
          </button>
        ) : null}
        <button
          type="button"
          onClick={onSend}
          disabled={sendDisabled}
          className="shrink-0 whitespace-nowrap rounded bg-blue-500 px-3 py-2 text-sm hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Send
        </button>
      </div>
      {afterRow ? <div className="mt-2">{afterRow}</div> : null}
    </div>
  )
}
