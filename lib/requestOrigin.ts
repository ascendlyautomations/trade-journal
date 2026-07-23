import { NextResponse } from "next/server"

/**
 * Public origin of an incoming request.
 *
 * Next.js often sets `request.url` / `nextUrl` to `http://localhost:3000`
 * even when the client connected via a LAN IP (e.g. Capacitor on a phone).
 * Prefer Host / X-Forwarded-* so redirects stay on the address the client used.
 */
export function getRequestOrigin(request: Request): string {
  const forwardedHost = request.headers
    .get("x-forwarded-host")
    ?.split(",")[0]
    ?.trim()
  const host = forwardedHost || request.headers.get("host")?.trim()

  const url = new URL(request.url)
  if (!host) return url.origin

  const forwardedProto = request.headers
    .get("x-forwarded-proto")
    ?.split(",")[0]
    ?.trim()
  const proto =
    forwardedProto || (url.protocol === "https:" ? "https" : "http")

  return `${proto}://${host}`
}

/** Absolute URL for `path`, using the client-facing origin (not localhost rewrite). */
export function absoluteUrlForRequest(request: Request, path: string): URL {
  const base = getRequestOrigin(request).replace(/\/$/, "")
  const normalized = path.startsWith("/") ? path : `/${path}`
  return new URL(`${base}${normalized}`)
}

/**
 * 307 redirect that never hardcodes a host.
 * Relative `Location` is resolved by the client against the URL it requested
 * (LAN IP on a phone, localhost in a desktop browser, production host in prod).
 */
export function redirectToPath(
  path: string,
  status: 307 | 302 | 303 | 308 = 307
): NextResponse {
  const normalized = path.startsWith("/") ? path : `/${path}`
  return new NextResponse(null, {
    status,
    headers: { Location: normalized },
  })
}
