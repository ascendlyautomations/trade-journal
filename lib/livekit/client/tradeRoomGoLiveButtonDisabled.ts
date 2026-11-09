/**
 * Trade Room "Go Live" primary button — disabled when reconnecting to a **public** session
 * from the server (use Stop stream / other controls instead).
 *
 * Do **not** use `status.live` here: the status API sets `live: true` for the broadcaster during
 * `visibility: "preparing"` (e.g. stale OBS prep session), which would incorrectly disable
 * this button while `isPublishing` is still false.
 */
export function tradeRoomGoLiveButtonDisabled(options: {
  isBusy: boolean
  accessTokenPresent: boolean
  /** Viewer-discoverable / room-public session only (see TradeRoomBroadcastPanel). */
  publicLive: boolean
}): boolean {
  return (
    options.isBusy ||
    !options.accessTokenPresent ||
    options.publicLive === true
  )
}
