import { cookies, headers } from "next/headers"

/**
 * Server-side native shell detection (cookie from /native + Capacitor UA).
 * Mirrors middleware `isNativeShellRequest` so SSR and the WebView agree.
 */
export async function isNativeShellRequest(): Promise<boolean> {
  const cookieStore = await cookies()
  if (cookieStore.get("tt_native")?.value === "1") return true
  const ua = (await headers()).get("user-agent") ?? ""
  return /TradeTraxsNative/i.test(ua)
}

/**
 * Capacitor iOS shell only. TradeTraxs ships an iOS app today; Android UA
 * with TradeTraxsNative would return false.
 */
export async function isNativeIosShellRequest(): Promise<boolean> {
  if (!(await isNativeShellRequest())) return false
  const ua = (await headers()).get("user-agent") ?? ""
  if (/Android/i.test(ua)) return false
  if (/iPhone|iPad|iPod/i.test(ua)) return true
  // Simulator / desktop-class iOS WebView often reports Macintosh.
  if (/TradeTraxsNative/i.test(ua)) return true
  // Cookie-only cold start after /native on iOS (UA still iOS-like).
  return !/Android/i.test(ua)
}
