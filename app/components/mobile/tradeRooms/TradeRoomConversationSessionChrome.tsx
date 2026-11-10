"use client"

import TradeRoomMobileSessionChromeStack from "./TradeRoomMobileSessionChromeStack"

type Props = {
  activeRoomId: string | null
  accessToken?: string | null
}

/**
 * In-room session chrome (mobile web) — stacked directly above the composer.
 */
export default function TradeRoomConversationSessionChrome({
  activeRoomId,
  accessToken = null,
}: Props) {
  if (!activeRoomId) return null

  return (
    <div
      className="shrink-0 border-t border-white/10 bg-[color:var(--tt-surface,#0d1117)]"
      data-tt-trade-room-session-chrome
    >
      <TradeRoomMobileSessionChromeStack
        placement="embedded"
        accessToken={accessToken}
      />
    </div>
  )
}
