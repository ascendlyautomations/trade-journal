import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

const CANONICAL_HOST = "www.tradetraxs.com"

const SECURITY_HEADERS: Record<string, string> = {
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}

function isLocalHost(host: string): boolean {
  const lower = host.toLowerCase()
  return (
    lower.startsWith("localhost") ||
    lower.startsWith("127.0.0.1") ||
    lower.endsWith(".local")
  )
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
