"use client"

import { useEffect, useMemo, useState } from "react"
import { Clock } from "lucide-react"
import {
  broadcastDurationWarningCopy,
  broadcastDurationWarningLevel,
  broadcastRemainingMs,
  formatBroadcastCountdown,
} from "@/lib/livekit/tradeRoomBroadcastDurationLimit.ts"

type Props = {
  expiresAt: string | null | undefined
  /** Only show for active broadcaster publishing (not viewers). */
  visible: boolean
}

export default function TradeRoomBroadcastDurationChrome({
  expiresAt,
  visible,
}: Props) {
  const [nowMs, setNowMs] = useState(() => Date.now())

  useEffect(() => {
    if (!visible || !expiresAt) return
    const id = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [visible, expiresAt])

  const remainingMs = useMemo(
    () => broadcastRemainingMs(expiresAt, nowMs),
    [expiresAt, nowMs]
  )
  const warningLevel = broadcastDurationWarningLevel(remainingMs)
  const warningCopy = broadcastDurationWarningCopy(warningLevel)

  if (!visible || !expiresAt || remainingMs == null) return null

  const warnTone =
    warningLevel === "5m" || warningLevel === "expired"
      ? "text-amber-600 dark:text-amber-400"
      : warningLevel === "15m"
        ? "text-muted-foreground"
        : "text-muted-foreground"

  return (
    <div
      className="space-y-1 rounded-lg border border-border/60 bg-card/80 px-3 py-2"
      data-testid="broadcast.duration.chrome"
    >
      <div className={`flex items-center gap-2 text-sm font-medium ${warnTone}`}>
        <Clock className="h-4 w-4 shrink-0" aria-hidden />
        <span>Time left: {formatBroadcastCountdown(remainingMs)}</span>
      </div>
      {warningCopy ? (
        <p
          className={`text-xs leading-snug ${
            warningLevel === "5m" || warningLevel === "expired"
              ? "text-amber-700 dark:text-amber-300"
              : "text-muted-foreground"
          }`}
        >
          {warningCopy}
        </p>
      ) : null}
    </div>
  )
}