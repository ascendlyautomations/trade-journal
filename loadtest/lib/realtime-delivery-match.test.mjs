import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  extractPostgresChangeRecord,
  matchesCorrelatedDelivery,
  deliveryTimeoutMsFromEnv,
} from "./realtime-delivery-match.js"

describe("realtime-delivery-match", () => {
  it("extracts record from postgres_changes payload", () => {
    const obj = {
      event: "postgres_changes",
      payload: {
        data: {
          table: "messages",
          record: { id: "m1", conversation_id: "c1", content: "hi" },
        },
      },
    }
    const rec = extractPostgresChangeRecord(obj)
    assert.equal(rec.id, "m1")
    assert.equal(rec.conversation_id, "c1")
  })

  it("matches DM by message id and conversation id", () => {
    assert.equal(
      matchesCorrelatedDelivery(
        { id: "m1", conversation_id: "c1" },
        { table: "messages", messageId: "m1", conversationId: "c1" }
      ),
      true
    )
    assert.equal(
      matchesCorrelatedDelivery(
        { id: "m2", conversation_id: "c1" },
        { table: "messages", messageId: "m1", conversationId: "c1" }
      ),
      false
    )
    assert.equal(
      matchesCorrelatedDelivery(
        { id: "m1", conversation_id: "c2" },
        { table: "messages", messageId: "m1", conversationId: "c1" }
      ),
      false
    )
  })

  it("matches room by message id and room id", () => {
    assert.equal(
      matchesCorrelatedDelivery(
        { id: "r1", room_id: "room-a" },
        { table: "room_messages", messageId: "r1", roomId: "room-a" }
      ),
      true
    )
  })

  it("parses delivery timeout env", () => {
    assert.equal(deliveryTimeoutMsFromEnv({}), 8000)
    assert.equal(deliveryTimeoutMsFromEnv({ LOADTEST_FULL_REALTIME_DELIVERY_TIMEOUT_MS: "12000" }), 12000)
  })
})
