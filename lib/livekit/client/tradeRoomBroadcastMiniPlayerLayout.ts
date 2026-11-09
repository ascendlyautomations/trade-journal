/** Shared floating mini-player position (aligned with TradeRoomLiveVoiceBar). */
export function tradeRoomBroadcastMiniPanelPosition(voiceSessionActive: boolean): string {
  const base =
    "fixed right-[max(0.5rem,env(safe-area-inset-right))] z-[9990] pointer-events-auto"
  const bottom = voiceSessionActive
    ? "max-md:bottom-[calc(var(--app-tab-bar-offset,0px)+7.5rem)] md:bottom-[calc(max(0.75rem,env(safe-area-inset-bottom))+7.5rem)]"
    : "max-md:bottom-[calc(var(--app-tab-bar-offset,0px)+0.5rem)] md:bottom-[max(0.75rem,env(safe-area-inset-bottom))]"
  return `${base} ${bottom}`
}
