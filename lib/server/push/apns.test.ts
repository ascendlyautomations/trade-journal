import assert from "node:assert/strict"
import test from "node:test"
import { buildApnsAlertPayloadBody } from "./apnsPayloadBody.ts"

test("buildApnsAlertPayloadBody includes default sound for visible alerts", () => {
  const body = buildApnsAlertPayloadBody({
    title: "Nick liked your trade",
    body: "Tap to view",
    href: "/trade/t1",
    notificationType: "like",
    badge: 2,
  })
  const parsed = JSON.parse(body) as {
    aps: { alert: { title: string; body: string }; sound?: string; badge?: number }
  }
  assert.equal(parsed.aps.alert.title, "Nick liked your trade")
  assert.equal(parsed.aps.sound, "default")
  assert.equal(parsed.aps.badge, 2)
})
