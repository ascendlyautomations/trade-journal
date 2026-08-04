"use client"

import type { ComponentProps } from "react"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import { usePlatformPresentation } from "./usePlatformPresentation"

export type PlatformSheetProps = ComponentProps<typeof DetailModalShell>

/**
 * Modal / sheet presentation adapter.
 * Native and web currently both use DetailModalShell (identical UI).
 * Call sites can migrate to PlatformSheet when ready for native sheets.
 */
export default function PlatformSheet(props: PlatformSheetProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (isNativeIos) {
    return <DetailModalShell {...props} />
  }
  return <DetailModalShell {...props} />
}
