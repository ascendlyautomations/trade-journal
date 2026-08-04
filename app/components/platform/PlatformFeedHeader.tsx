"use client"

import FeedModeToggle, {
  type FeedMode,
} from "@/app/components/feed/FeedModeToggle"
import NativeIosFeedHeader from "./native/NativeIosFeedHeader"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformFeedHeaderProps = {
  mode: FeedMode
  onModeChange: (mode: FeedMode) => void
}

/**
 * Native iOS Feed chrome only (sticky compact header).
 * Web returns null — use PlatformFeedModeToggle inside the feed column.
 */
export default function PlatformFeedHeader({
  mode,
  onModeChange,
}: PlatformFeedHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null
  return <NativeIosFeedHeader mode={mode} onModeChange={onModeChange} />
}

/**
 * In-flow Following / Global control for web (desktop + mobile Safari).
 * Hidden on native iOS where the control lives in PlatformFeedHeader.
 */
export function PlatformFeedModeToggle({
  mode,
  onModeChange,
}: PlatformFeedHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) return null
  return <FeedModeToggle mode={mode} onModeChange={onModeChange} />
}
