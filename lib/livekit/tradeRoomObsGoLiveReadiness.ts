/**
 * Mirrors TradeRoomBroadcastPanel "Go live to room" enablement (OBS prep only).
 * Keep in sync when changing disabled={...} for that button.
 */
export function tradeRoomObsGoLiveToRoomEnabled(options: {
  obsPreparingHost: boolean
  isBusy: boolean
  primaryMediaPublisherConnected: boolean | null | undefined
}): boolean {
  return (
    options.obsPreparingHost &&
    !options.isBusy &&
    options.primaryMediaPublisherConnected === true
  )
}
