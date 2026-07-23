import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

const CANONICAL_HOST = "www.tradetraxs.com"

const SECURITY_HEADERS: Record<string, string> = {
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}

function isPrivateLanIpv4(hostWithoutPort: string): boolean {
  return /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[0-1])\.)\d/.test(hostWithoutPort)
}

function isLocalHost(host: string): boolean {
  const lower = host.toLowerCase()
  const hostWithoutPort = lower.split(":")[0] ?? lower
  return (
    lower.startsWith("localhost") ||
    lower.startsWith("127.0.0.1") ||
    lower.endsWith(".local") ||
    // Capacitor physical-device dev loads http://<Mac-LAN-IP>:3000
    isPrivateLanIpv4(hostWithoutPort)
  )
}

function isNativeShellRequest(request: NextRequest): boolean {
  const ua = request.headers.get("user-agent") ?? ""
  if (/TradeTraxsNative/i.test(ua)) return true
  if (request.cookies.get("tt_native")?.value === "1") return true
  return false
}

export function middleware(request: NextRequest) {
  const host = request.headers.get("host") ?? ""
  const forwardedProto = request.headers.get("x-forwarded-proto")
  const url = request.nextUrl.clone()

  if (!isLocalHost(host)) {
    if (host !== CANONICAL_HOST) {
      url.host = CANONICAL_HOST
      url.protocol = "https:"
      return NextResponse.redirect(url, 308)
    }

    if (forwardedProto === "http") {
      url.protocol = "https:"
      return NextResponse.redirect(url, 308)
    }
  }

  // Capacitor server.url is the site origin (not /native). Send native `/`
  // through the auth-aware cold-start entry without touching web marketing.
  //
  // Must use an absolute URL here: Next's middleware adapter does
  // `new NextURL(Location)` without a base (see next/dist server web adapter),
  // so a relative Location like "/native" throws TypeError: Invalid URL.
  if (url.pathname === "/" && isNativeShellRequest(request)) {
    const nativeUrl = request.nextUrl.clone()
    nativeUrl.pathname = "/native"
    nativeUrl.search = ""
    nativeUrl.hash = ""
    const response = NextResponse.redirect(nativeUrl, 307)
    for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
      response.headers.set(key, value)
    }
    return response
  }

  const requestHeaders = new Headers(request.headers)
  requestHeaders.set("x-pathname", url.pathname)

  const response = NextResponse.next({
    request: { headers: requestHeaders },
  })

  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    response.headers.set(key, value)
  }

  return response
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
}
