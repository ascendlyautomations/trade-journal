import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { filterMessagesForUser } from "./conversationMessageUtils.ts"

describe("filterMessagesForUser", () => {
  it("drops delete-for-everyone and per-user deleted ids", () => {
    const rows = [
      { id: "a", deleted_for_everyone: false },
      { id: "b", deleted_for_everyone: true },
      { id: "c", deleted_for_everyone: false },
    ]
    const filtered = filterMessagesForUser(rows, new Set(["c"]))
    assert.deepEqual(
      filtered.map((row) => row.id),
      ["a"]
    )
  })
})
