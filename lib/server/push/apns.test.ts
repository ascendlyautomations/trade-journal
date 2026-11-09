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

test("buildApnsAlertPayloadBody includes Trade Room section and message ids", () => {
  const body = buildApnsAlertPayloadBody({
    title: "Desk",
    body: "Nick: hi",
    href: "/community?room=desk&section=sec-1&message=msg-9",
    notificationType: "room_message",
    roomId: "room-uuid",
    roomSlug: "desk",
    sectionId: "sec-1",
    messageId: "msg-9",
    sectionName: "general",
  })
  const parsed = JSON.parse(body) as Record<string, string>
  assert.equal(parsed.sectionId, "sec-1")
  assert.equal(parsed.messageId, "msg-9")
  assert.equal(parsed.sectionName, "general")
  assert.equal(parsed.href, "/community?room=desk&section=sec-1&message=msg-9")
})
