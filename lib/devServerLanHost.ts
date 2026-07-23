import { networkInterfaces } from "node:os"

/**
 * LAN IPv4 for Capacitor physical-device → Next.js dev server access.
 * Shared by capacitor.config.ts and next.config.ts (allowedDevOrigins).
 */
export function resolveDevServerLanHost(): string | null {
  const override = process.env.CAPACITOR_DEV_HOST?.trim()
  if (override) return override

  let nets: ReturnType<typeof networkInterfaces>
  try {
    nets = networkInterfaces()
  } catch {
    return null
  }
  const candidates: string[] = []

  for (const entries of Object.values(nets)) {
    for (const net of entries ?? []) {
      const family = net.family
      const isV4 = family === "IPv4" || family === 4
      if (!isV4 || net.internal) continue
      candidates.push(net.address)
    }
  }

  const privateLan = candidates.find((ip) =>
    /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[0-1])\.)/.test(ip)
  )
  return privateLan ?? candidates[0] ?? null
}

/** Hostnames Next.js must allow for LAN WebView fetches in development. */
export function resolveAllowedDevOrigins(): string[] {
  const host = resolveDevServerLanHost()
  if (!host || host === "localhost" || host === "127.0.0.1") return []
  // Include both forms — Next matches Host / Origin host variously.
  return [host, `${host}:3000`]
}
