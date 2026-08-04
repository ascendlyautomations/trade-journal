"use client"

import type { ComponentProps } from "react"
import ProfileHeader from "@/app/components/profile/ProfileHeader"
import { usePlatformPresentation } from "./usePlatformPresentation"

export type PlatformProfileHeaderProps = ComponentProps<typeof ProfileHeader>

/**
 * Profile header presentation adapter.
 * Native and web currently both render the existing ProfileHeader.
 */
export default function PlatformProfileHeader(props: PlatformProfileHeaderProps) {
  const { isNativeIos } = usePlatformPresentation()
  // Explicit branch keeps future native redesign local to this file.
  if (isNativeIos) {
    return <ProfileHeader {...props} />
  }
  return <ProfileHeader {...props} />
}
