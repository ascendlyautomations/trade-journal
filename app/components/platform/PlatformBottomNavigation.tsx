"use client"

import { usePlatformPresentation } from "./usePlatformPresentation"
import NativeIosBottomNavigation from "./native/NativeIosBottomNavigation"

/**
 * Bottom navigation presentation adapter.
 * Web: nothing (same as before). Native iOS: existing tab bar.
 */
export default function PlatformBottomNavigation() {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null
  return <NativeIosBottomNavigation />
}
