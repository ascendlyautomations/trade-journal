import { describe, it, beforeEach } from "node:test"
import { CONVERSATION_LRU_MAX_SIZE, ConversationLruStore, } from "./conversationLruStore.ts"
import assert from "node:assert/strict"

type TestConversationEntry = { conversationId: string }

describe("ConversationLruStore", () => {
  let lru: ConversationLruStore<TestConversationEntry>

  beforeEach(() => {
    lru = new ConversationLruStore<TestConversationEntry>()
  })

  it("evicts the least recently used entry at capacity", () => {
    for (let i = 0; i < CONVERSATION_LRU_MAX_SIZE; i++) {
      lru.set(`key-${i}`, {
        conversationId: `conv-${i}`,
        lastAccessedAt: i,
      })
    }
    assert.equal(lru.size(), CONVERSATION_LRU_MAX_SIZE)

    lru.set("key-new", {
      conversationId: "conv-new",
      lastAccessedAt: Date.now(),
    })

    assert.equal(lru.size(), CONVERSATION_LRU_MAX_SIZE)
    assert.equal(lru.peek("key-0"), null)
    assert.ok(lru.peek("key-new"))
  })

  it("does not evict the pinned key", () => {
    for (let i = 0; i < CONVERSATION_LRU_MAX_SIZE; i++) {
      lru.set(`key-${i}`, {
        conversationId: `conv-${i}`,
        lastAccessedAt: i,
      })
    }

    lru.setPinned("key-0")
    lru.set("key-overflow", {
      conversationId: "conv-overflow",
      lastAccessedAt: Date.now(),
    })

    assert.ok(lru.peek("key-0"))
    assert.equal(lru.peek("key-1"), null)
  })

  it("promotes on get and touch", () => {
    lru.set("key-a", { conversationId: "a", lastAccessedAt: 1 })
    lru.set("key-b", { conversationId: "b", lastAccessedAt: 2 })
    lru.set("key-c", { conversationId: "c", lastAccessedAt: 3 })

    lru.get("key-a")
    assert.equal(lru.oldestKey(), "key-b")

    lru.touch("key-b")
    assert.equal(lru.oldestKey(), "key-c")
  })
})
export {}
