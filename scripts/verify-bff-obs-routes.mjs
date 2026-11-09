#!/usr/bin/env node
/**
 * Smoke-check OBS LiveKit BFF routes return JSON (not HTML shell).
 * Usage: BFF_BASE_URL=https://www.tradetraxs.com node scripts/verify-bff-obs-routes.mjs
 */
const base = (process.env.BFF_BASE_URL || "https://www.tradetraxs.com").replace(/\/$/, "")

const checks = [
  {
    name: "obs/credentials",
    method: "POST",
    path: "/api/livekit/broadcast/obs/credentials",
    body: JSON.stringify({
      roomId: "00000000-0000-0000-0000-000000000001",
      sessionId: "00000000-0000-0000-0000-000000000002",
    }),
  },
  {
    name: "obs/status",
    method: "GET",
    path:
      "/api/livekit/broadcast/obs/status?roomId=00000000-0000-0000-0000-000000000001&sessionId=00000000-0000-0000-0000-000000000002",
  },
  {
    name: "broadcast/start (sanity)",
    method: "POST",
    path: "/api/livekit/broadcast/start",
    body: JSON.stringify({
      roomId: "00000000-0000-0000-0000-000000000001",
      videoSource: "obs",
    }),
  },
]

let failed = false

for (const check of checks) {
  const url = `${base}${check.path}`
  const res = await fetch(url, {
    method: check.method,
    headers: { "Content-Type": "application/json" },
    body: check.body,
  })
  const ct = res.headers.get("content-type") || ""
  const text = (await res.text()).slice(0, 200)
  const html = ct.includes("text/html") || text.trimStart().startsWith("<!")
  const ok = !html
  console.log(
    `${ok ? "OK" : "FAIL"} ${check.name} ${res.status} ${ct} ${url}`
  )
  if (!ok) {
    failed = true
    console.log(`  body[0:200]=${JSON.stringify(text)}`)
  }
}

if (failed) {
  console.error(
    "\nOBS BFF routes returned HTML — deploy the latest Next.js build or fix BFF_BASE_URL."
  )
  process.exit(1)
}

console.log("\nAll OBS BFF smoke checks returned non-HTML responses.")
