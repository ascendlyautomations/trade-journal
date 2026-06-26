const assert = require("node:assert/strict")
const { describe, it, beforeEach } = require("node:test")
const {
  CONVERSATION_LRU_MAX_SIZE,
  ConversationLruStore,
} = require("./conversationLruStore.ts")

describe("ConversationLruStore", () => {
  let lru

  beforeEach(() => {
    lru = new ConversationLruStore()
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
