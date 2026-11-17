"use client"

import { TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX } from "@/lib/livekit/tradeRoomBroadcastStreamTitle.ts"

type Props = {
  value: string
  onChange: (value: string) => void
  disabled?: boolean
  id?: string
  className?: string
}

export default function TradeRoomBroadcastStreamTitleField({
  value,
  onChange,
  disabled = false,
  id = "broadcast-stream-title",
  className = "",
}: Props) {
  const len = value.trim().length
  const canSubmit = len > 0 && len <= TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX

  return (
    <div className={`space-y-1.5 ${className}`.trim()}>
      <label htmlFor={id} className="text-xs font-semibold uppercase tracking-wide text-gray-500">
        Stream title
      </label>
      <input
        id={id}
        type="text"
        value={value}
        disabled={disabled}
        maxLength={TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX}
        onChange={(e) => onChange(e.target.value)}
        placeholder="e.g. Trading NY Session — NQ Futures"
        className="w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white placeholder:text-gray-500 focus:border-violet-400/50 focus:outline-none disabled:opacity-50"
        autoComplete="off"
      />
      <p className="text-[11px] text-gray-500">
        {len}/{TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX}
        {!canSubmit && len === 0 ? " · Required before going live" : null}
      </p>
    </div>
  )
}
