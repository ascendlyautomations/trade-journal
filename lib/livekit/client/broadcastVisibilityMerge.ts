import type { TradeRoomBroadcastVideoSource } from "../tradeRoomBroadcastVoiceMode.ts"

/**
 * Normalize `publicLive` + `visibility` after merging an API payload with previous client state.
 *
 * When `visibility` is omitted (e.g. lite status poll), we must not treat "missing" as `public`;
 * that incorrectly ended OBS private preparation UI.
 */
export function resolveBroadcastLiveVisibility(options: {
  mergedLive: boolean
  mergedBroadcastSessionId: string | undefined
  mergedVideoSource: TradeRoomBroadcastVideoSource | undefined
  mergedVisibility: "public" | "preparing" | undefined
  mergedPublicLive: boolean | undefined
  prevLive: boolean
  prevBroadcastSessionId: string | undefined
  prevVisibility: "public" | "preparing" | undefined
  prevPublicLive: boolean | undefined
}): {
  visibility: "public" | "preparing" | undefined
  publicLive: boolean | undefined
} {
  if (!options.mergedLive) {
    return { visibility: undefined, publicLive: false }
  }

  const sameSession =
    Boolean(options.mergedBroadcastSessionId) &&
    options.mergedBroadcastSessionId === options.prevBroadcastSessionId

  const mergedVis = options.mergedVisibility
  const hasExplicitVis =
    mergedVis === "public" || mergedVis === "preparing"

  const effectiveVis: "public" | "preparing" | undefined = hasExplicitVis
    ? mergedVis
    : sameSession &&
        (options.prevVisibility === "public" ||
          options.prevVisibility === "preparing")
      ? options.prevVisibility
      : undefined

  const plIn = options.mergedPublicLive
  const effectivePublicLive: boolean | undefined =
    typeof plIn === "boolean"
      ? plIn
      : sameSession && typeof options.prevPublicLive === "boolean"
        ? options.prevPublicLive
        : undefined

  if (effectiveVis === "public") {
    return { visibility: "public", publicLive: true }
  }
  if (effectiveVis === "preparing") {
    return { visibility: "preparing", publicLive: false }
  }
  if (effectivePublicLive === true) {
    return { visibility: "public", publicLive: true }
  }
  if (effectivePublicLive === false) {
    const vis =
      options.mergedVideoSource === "obs" ? "preparing" : "public"
    return {
      visibility: vis,
      publicLive: vis === "public",
    }
  }

  if (options.mergedVideoSource === "obs") {
    return { visibility: "preparing", publicLive: false }
  }
  return { visibility: "public", publicLive: true }
}
