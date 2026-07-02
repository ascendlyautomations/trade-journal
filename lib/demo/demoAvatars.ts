/** Stable placeholder avatars for demo users — same pipeline as production (https URLs). */
import { demoChartImageUrl } from "./demoAssets"

export function demoAvatarUrl(userId: string): string {
  return `https://picsum.photos/seed/tradetraxs-avatar-${encodeURIComponent(userId)}/256/256`
}

export function demoReelThumbnailUrl(reelId: string): string {
  return demoChartImageUrl(`reel-${reelId}`)
}

export function demoRoomImageUrl(roomId: string): string {
  return `https://picsum.photos/seed/tradetraxs-room-${encodeURIComponent(roomId)}/256/256`
}
