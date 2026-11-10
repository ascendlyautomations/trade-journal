"use client"

import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import { acknowledgeTradeRoomBroadcastViewerRemoval } from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

export default function TradeRoomBroadcastViewerRemovalOverlay() {
  const broadcast = useTradeRoomBroadcast()
  const notice = broadcast.viewerStreamRemovalNotice

  if (!notice) return null

  const title = notice.kind === "banned" ? "Removed & blocked" : "Removed from stream"
  const body =
    notice.kind === "banned"
      ? "The host removed you from this livestream and blocked you from rejoining this session."
      : "The host removed you from this livestream."

  return (
    <div className="fixed inset-0 z-[9500] hidden items-center justify-center bg-black/70 p-4 md:flex">
      <div
        className="w-full max-w-sm rounded-xl border border-white/10 bg-zinc-900 p-5 text-white shadow-2xl"
        role="alertdialog"
        aria-labelledby="broadcast-removal-title"
        aria-describedby="broadcast-removal-body"
      >
        <h2 id="broadcast-removal-title" className="text-lg font-semibold">
          {title}
        </h2>
        <p id="broadcast-removal-body" className="mt-2 text-sm text-white/75">
          {body}
        </p>
        <button
          type="button"
          className="mt-5 w-full rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-500"
          onClick={() => acknowledgeTradeRoomBroadcastViewerRemoval()}
        >
          OK
        </button>
      </div>
    </div>
  )
}
