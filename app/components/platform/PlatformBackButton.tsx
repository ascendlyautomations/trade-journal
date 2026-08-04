"use client"

import type { ButtonHTMLAttributes, ReactNode } from "react"
import { usePlatformPresentation } from "./usePlatformPresentation"

type PlatformBackButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  /** Existing back control — preferred over inventing new chrome. */
  children?: ReactNode
}

/**
 * Back-button presentation adapter.
 * Renders the provided children/button props identically on both platforms.
 */
export default function PlatformBackButton({
  children,
  ...props
}: PlatformBackButtonProps) {
  const { isNativeIos } = usePlatformPresentation()
  if (children) {
    return <>{children}</>
  }
  // Explicit branch for future native system back affordances.
  if (isNativeIos) {
    return <button type="button" {...props} />
  }
  return <button type="button" {...props} />
}
