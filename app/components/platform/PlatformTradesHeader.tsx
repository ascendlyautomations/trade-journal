"use client"

import { useState, type ComponentProps } from "react"
import NativeIosTradesHeader from "./native/NativeIosTradesHeader"
import NativeIosTradesFilterSheet from "./native/NativeIosTradesFilterSheet"
import { usePlatformPresentation } from "./usePlatformPresentation"
import { hapticLight } from "@/lib/nativeHaptics"

type FilterSheetProps = Omit<
  ComponentProps<typeof NativeIosTradesFilterSheet>,
  "open" | "onClose"
>

/**
 * Native iOS Trades page chrome: compact header + filter sheet.
 * Web returns null — existing TradeFilterBar remains in TradesPageMainContent.
 */
export default function PlatformTradesHeader(props: FilterSheetProps) {
  const { isNativeIos } = usePlatformPresentation()
  const [filterOpen, setFilterOpen] = useState(false)

  if (!isNativeIos) return null

  return (
    <>
      <NativeIosTradesHeader
        onOpenFilters={() => {
          hapticLight("filters")
          setFilterOpen(true)
        }}
      />
      <NativeIosTradesFilterSheet
        {...props}
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
      />
    </>
  )
}
