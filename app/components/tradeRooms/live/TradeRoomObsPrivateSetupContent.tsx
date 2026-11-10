"use client"

import type { RefObject } from "react"
import { Copy, Eye, EyeOff } from "lucide-react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import {
  copyObsFieldToClipboard,
  setObsStreamKeyRevealed,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

export type TradeRoomObsPrivateSetupContentProps = {
  videoRef: (el: HTMLVideoElement | null) => void
  containerRef?: RefObject<HTMLDivElement | null>
  onRetryCredentials: () => void
  onRegenerateCredentials: () => void
  obsPreparingHost: boolean
  encoderConnected: boolean
  waitingForObsEncoder: boolean
}

export default function TradeRoomObsPrivateSetupContent({
  videoRef,
  containerRef,
  onRetryCredentials,
  onRegenerateCredentials,
  obsPreparingHost,
  encoderConnected,
  waitingForObsEncoder,
}: TradeRoomObsPrivateSetupContentProps) {
  const broadcast = useTradeRoomBroadcast()

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <div className="rounded-lg border border-violet-500/30 bg-zinc-950/80 p-4 text-sm text-gray-200">
        <p className="font-semibold text-violet-200">OBS Studio — private setup</p>
        <p className="mt-2 text-xs text-gray-400">
          Viewers cannot see this room until you tap{" "}
          <span className="font-semibold text-white">Go live to room</span>. Use{" "}
          <span className="font-semibold text-white">Cancel setup</span> to revoke ingress
          and end this session.
        </p>
        {broadcast.obsBroadcastBootstrapping ? (
          <p className="mt-3 text-xs text-gray-500">Connecting to TradeTraxs…</p>
        ) : null}
        {broadcast.obsStudio?.credentialsBusy ? (
          <p className="mt-3 text-xs text-amber-200/90">Generating OBS credentials…</p>
        ) : null}
        {broadcast.obsStudio?.credentialsError ? (
          <div
            className={`mt-3 space-y-2 rounded border p-3 text-xs ${
              broadcast.obsStudio.credentialsLostOrUnavailable
                ? "border-amber-400/35 bg-amber-950/35"
                : "border-red-400/30 bg-red-950/40"
            }`}
          >
            <p
              className={
                broadcast.obsStudio.credentialsLostOrUnavailable
                  ? "text-amber-100/95"
                  : "text-red-200"
              }
            >
              {broadcast.obsStudio.credentialsError}
            </p>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={broadcast.isBusy || broadcast.obsStudio.credentialsBusy}
                onClick={() => void onRetryCredentials()}
                className="rounded border border-white/20 px-2 py-1 text-xs font-semibold text-white hover:bg-white/10 disabled:opacity-50"
              >
                {broadcast.obsStudio.credentialsLostOrUnavailable ? "Try again" : "Retry"}
              </button>
              <button
                type="button"
                disabled={broadcast.isBusy || broadcast.obsStudio.credentialsBusy}
                onClick={() => void onRegenerateCredentials()}
                className="rounded border border-amber-400/40 px-2 py-1 text-xs font-semibold text-amber-100 hover:bg-amber-500/10 disabled:opacity-50"
              >
                Regenerate stream key
              </button>
            </div>
          </div>
        ) : null}
        {broadcast.obsStudio?.rtmpUrl ? (
          <div className="mt-4 space-y-3 text-xs">
            <p className="text-gray-400">
              In OBS: <span className="text-gray-300">Settings → Stream</span>. Set{" "}
              <span className="text-gray-300">Service</span> to{" "}
              <span className="text-gray-300">Custom...</span>. Paste the server URL and stream
              key, then click <span className="text-gray-300">Start Streaming</span> in OBS.
            </p>
            <div className="space-y-1">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Server (RTMP URL)
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <code className="max-w-full flex-1 break-all rounded bg-black/50 px-2 py-1 text-[11px] text-violet-200">
                  {broadcast.obsStudio.rtmpUrl}
                </code>
                <button
                  type="button"
                  className="inline-flex shrink-0 items-center gap-1 rounded border border-white/15 px-2 py-1 text-[11px] hover:bg-white/5"
                  onClick={() =>
                    void copyObsFieldToClipboard(broadcast.obsStudio!.rtmpUrl!)
                  }
                >
                  <Copy className="h-3 w-3" aria-hidden />
                  Copy
                </button>
              </div>
            </div>
            <div className="space-y-1">
              <div className="flex flex-wrap items-center gap-2 text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                <span>Stream key</span>
                <button
                  type="button"
                  className="inline-flex items-center gap-1 rounded border border-white/10 px-2 py-0.5 normal-case text-gray-300 hover:bg-white/5"
                  onClick={() =>
                    setObsStreamKeyRevealed(!broadcast.obsStudio?.revealedStreamKey)
                  }
                >
                  {broadcast.obsStudio?.revealedStreamKey ? (
                    <>
                      <EyeOff className="h-3 w-3" /> Hide
                    </>
                  ) : (
                    <>
                      <Eye className="h-3 w-3" /> Show
                    </>
                  )}
                </button>
              </div>
              {broadcast.obsStudio.revealedStreamKey ? (
                <div className="flex flex-wrap items-center gap-2">
                  <code className="max-w-full flex-1 break-all rounded bg-black/50 px-2 py-1 text-[11px] text-amber-100">
                    {broadcast.obsStudio.revealedStreamKey}
                  </code>
                  <button
                    type="button"
                    className="inline-flex shrink-0 items-center gap-1 rounded border border-white/15 px-2 py-1 text-[11px] hover:bg-white/5"
                    onClick={() =>
                      void copyObsFieldToClipboard(
                        broadcast.obsStudio!.revealedStreamKey!
                      )
                    }
                  >
                    <Copy className="h-3 w-3" aria-hidden />
                    Copy
                  </button>
                </div>
              ) : (
                <p className="text-gray-500">
                  Hidden — tap Show to reveal. Do not share this key outside OBS.
                </p>
              )}
            </div>
          </div>
        ) : !broadcast.obsStudio?.credentialsBusy &&
          !broadcast.obsBroadcastBootstrapping &&
          !broadcast.obsStudio?.credentialsError ? (
          <p className="mt-3 text-xs text-gray-500">Waiting for streaming credentials…</p>
        ) : null}
      </div>

      <div
        className={`text-xs ${
          encoderConnected ? "font-medium text-emerald-300/90" : "text-amber-200/90"
        }`}
      >
        {encoderConnected
          ? "OBS connected — private preview below."
          : waitingForObsEncoder
            ? "Waiting for OBS — start streaming in OBS with the credentials above."
            : "Waiting for OBS encoder…"}
      </div>

      <div
        ref={containerRef}
        className="relative min-h-[200px] w-full overflow-hidden rounded-lg border border-white/10 bg-black aspect-video"
      >
        {broadcast.isPublishing && broadcast.broadcasterPreviewError ? (
          <div className="absolute inset-0 z-10 flex items-center justify-center bg-black/80 px-4 text-center text-sm text-amber-200">
            {broadcast.broadcasterPreviewError}
          </div>
        ) : null}
        {!encoderConnected && obsPreparingHost ? (
          <div className="pointer-events-none absolute inset-0 z-[5] flex items-center justify-center bg-black/70 px-4 text-center text-sm text-gray-300">
            No preview yet — connect OBS to see your program feed here (private).
          </div>
        ) : null}
        <video
          ref={videoRef}
          className="h-full w-full object-contain"
          playsInline
          muted
          autoPlay
        />
      </div>
    </div>
  )
}
