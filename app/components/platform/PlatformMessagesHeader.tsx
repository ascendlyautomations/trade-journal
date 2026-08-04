"use client"

import type { ReactNode } from "react"
import NativeIosMessagesInboxActions from "./native/NativeIosMessagesInboxActions"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformMessagesHeaderProps = {
  onPersonalChat: () => void
  onGroupChat: () => void
}

/**
 * Native iOS Messages inbox chrome — action row only (no title header).
 * Web returns null; use PlatformMessagesWebInboxActions for the web controls.
 */
export default function PlatformMessagesHeader({
  onPersonalChat,
  onGroupChat,
}: PlatformMessagesHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (!isNativeIos) return null
  return (
    <NativeIosMessagesInboxActions
      onPersonalChat={onPersonalChat}
      onGroupChat={onGroupChat}
    />
  )
}

/**
 * In-flow Messages inbox actions for web (desktop + mobile Safari).
 * Hidden on native iOS where PlatformMessagesHeader owns the action row.
 */
export function PlatformMessagesWebInboxActions({
  children,
}: {
  children: ReactNode
}) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) return null
  return <>{children}</>
}
