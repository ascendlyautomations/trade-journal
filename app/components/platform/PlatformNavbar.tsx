"use client"

import { usePlatformPresentation } from "./usePlatformPresentation"
import NativeIosNavbar from "./native/NativeIosNavbar"
import WebNavbar from "./web/WebNavbar"

/**
 * Top app navigation presentation adapter.
 * Native and web currently both render the existing Navbar (identical UI).
 */
export default function PlatformNavbar() {
  const { isNativeIos } = usePlatformPresentation()
  return isNativeIos ? <NativeIosNavbar /> : <WebNavbar />
}
