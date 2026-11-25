"use client"

import { useEffect, useState } from "react"
import type { BroadcastFloatingReaction } from "@/lib/livekit/client/tradeRoomBroadcastReaction.ts"

const LIFETIME_MS = 2_800

type ActiveReaction = BroadcastFloatingReaction & { expiresAt: number }

type Props = {
  reactions: BroadcastFloatingReaction[]
  className?: string
}

export default function BroadcastLiveReactionOverlay({
  reactions,
  className = "",
}: Props) {
  const [active, setActive] = useState<ActiveReaction[]>([])

  useEffect(() => {
    const latest = reactions.at(-1)
    if (!latest) return
    const now = Date.now()
    setActive((prev) => {
      const pruned = prev.filter((item) => item.expiresAt > now)
      if (pruned.some((item) => item.id === latest.id)) return pruned
      return [
        ...pruned.slice(-24),
        { ...latest, expiresAt: now + LIFETIME_MS + Math.random() * 400 },
      ]
    })
  }, [reactions])

  useEffect(() => {
    const timer = window.setInterval(() => {
      const now = Date.now()
      setActive((prev) => prev.filter((item) => item.expiresAt > now))
    }, 280)
    return () => window.clearInterval(timer)
  }, [])

  if (active.length === 0) return null

  return (
    <div
      className={`pointer-events-none absolute inset-0 overflow-hidden ${className}`.trim()}
      aria-hidden
    >
      {active.map((item) => (
        <span
          key={item.id}
          className="absolute text-3xl drop-shadow-md animate-broadcast-reaction-float"
          style={{
            left: `${item.originX * 100}%`,
            bottom: "18%",
            animationDuration: `${LIFETIME_MS}ms`,
          }}
        >
          {item.emoji}
        </span>
      ))}
    </div>
  )
}