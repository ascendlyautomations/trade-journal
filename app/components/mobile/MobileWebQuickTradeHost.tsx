"use client"

import dynamic from "next/dynamic"
import { useCallback, useEffect, useState } from "react"
import { useUserProfile } from "@/lib/useUserProfile"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { usePhoneWebTouchTarget } from "@/lib/usePhoneWebTouchTarget"
import {
  MOBILE_WEB_OPEN_QUICK_TRADE_EVENT,
} from "@/lib/mobileWebQuickTrade"

const QuickTradeModal = dynamic(
  () => import("@/app/components/QuickTradeModal"),
  { ssr: false }
)

/** Global Quick Trade entry for mobile web Create hub. */
export default function MobileWebQuickTradeHost() {
  const nativeIos = useIsNativeIos()
  const phoneWeb = usePhoneWebTouchTarget()
  const { user } = useUserProfile()
  const [open, setOpen] = useState(false)

  const onClose = useCallback(() => setOpen(false), [])

  useEffect(() => {
    if (nativeIos || !phoneWeb) return
    const onOpen = () => setOpen(true)
    window.addEventListener(MOBILE_WEB_OPEN_QUICK_TRADE_EVENT, onOpen)
    return () =>
      window.removeEventListener(MOBILE_WEB_OPEN_QUICK_TRADE_EVENT, onOpen)
  }, [nativeIos, phoneWeb])

  if (nativeIos || !phoneWeb) return null

  return (
    <QuickTradeModal
      open={open}
      onClose={onClose}
      userId={user?.id ?? null}
    />
  )
}
