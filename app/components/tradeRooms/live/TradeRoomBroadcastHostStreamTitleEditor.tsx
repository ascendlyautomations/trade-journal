"use client"

import { useEffect, useState } from "react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastStreamTitleField from "./TradeRoomBroadcastStreamTitleField.tsx"
import { patchTradeRoomBroadcastStreamTitle } from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import { TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX } from "@/lib/livekit/tradeRoomBroadcastStreamTitle.ts"

type Props = {
  roomId: string
  accessToken: string
  sessionId: string
  compact?: boolean
}

export default function TradeRoomBroadcastHostStreamTitleEditor({
  roomId,
  accessToken,
  sessionId,
  compact = false,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const serverTitle = broadcast.status.streamTitle?.trim() ?? ""
  const [draft, setDraft] = useState(serverTitle)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setDraft(serverTitle)
  }, [serverTitle])

  const trimmed = draft.trim()
  const dirty = trimmed !== serverTitle
  const canSave =
    trimmed.length > 0 && trimmed.length <= TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX

  async function onSave() {
    if (!dirty || !canSave || saving) return
    setSaving(true)
    setError(null)
    try {
      await patchTradeRoomBroadcastStreamTitle({
        roomId,
        sessionId,
        accessToken,
        streamTitle: trimmed,
      })
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save title.")
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className={compact ? "space-y-2" : "mt-3 space-y-2 rounded-lg border border-white/10 bg-black/20 p-3"}>
      <TradeRoomBroadcastStreamTitleField
        value={draft}
        onChange={setDraft}
        disabled={saving || broadcast.isBusy}
      />
      {dirty ? (
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            disabled={!canSave || saving}
            onClick={() => void onSave()}
            className="rounded-lg bg-violet-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-violet-500 disabled:opacity-50"
          >
            {saving ? "Saving…" : "Save title"}
          </button>
          <button
            type="button"
            disabled={saving}
            onClick={() => setDraft(serverTitle)}
            className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-gray-300 hover:bg-white/5"
          >
            Reset
          </button>
        </div>
      ) : null}
      {error ? <p className="text-xs text-red-300">{error}</p> : null}
    </div>
  )
}
