import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  classifyServerReadError,
  createReadTimeoutSignal,
  isTransientNetworkError,
  isTransientServerReadError,
  withServerReadRetry,
} from "./serverReadRetry.ts"

describe("serverReadRetry", () => {
  it("classifies undici socket close as transient network", () => {
    const err = new TypeError("fetch failed", {
      cause: { code: "UND_ERR_SOCKET", message: "other side closed" },
    })
    assert.equal(isTransientNetworkError(err), true)
    assert.equal(classifyServerReadError(err), "transient_network")
    assert.equal(isTransientServerReadError(err), true)
  })

  it("retries transient socket disconnect then succeeds", async () => {
    let calls = 0
    const result = await withServerReadRetry(async () => {
      calls += 1
      if (calls === 1) {
        throw new TypeError("fetch failed", {
          cause: { code: "UND_ERR_SOCKET" },
        })
      }
      return "ok"
    })
    assert.equal(result, "ok")
    assert.equal(calls, 2)
  })

  it("stops after repeated network failure", async () => {
    let calls = 0
    await assert.rejects(
      () =>
        withServerReadRetry(
          async () => {
            calls += 1
            throw new TypeError("fetch failed", {
              cause: { code: "UND_ERR_SOCKET" },
            })
          },
          { maxAttempts: 3 }
        ),
      (err: unknown) => err instanceof TypeError
    )
    assert.equal(calls, 3)
  })

  it("does not retry PGRST202 missing RPC", async () => {
    let calls = 0
    await assert.rejects(
      () =>
        withServerReadRetry(async () => {
          calls += 1
          throw Object.assign(new Error("Could not find the function"), {
            code: "PGRST202",
          })
        }),
      /Could not find/
    )
    assert.equal(calls, 1)
  })

  it("does not retry 403-style postgrest errors", async () => {
    let calls = 0
    await assert.rejects(() =>
      withServerReadRetry(async () => {
        calls += 1
        throw { code: "42501", message: "permission denied" }
      })
    )
    assert.equal(calls, 1)
  })

  it("aborts read timeout signal", async () => {
    const handle = createReadTimeoutSignal(30)
    await new Promise((r) => setTimeout(r, 50))
    assert.equal(handle.signal.aborted, true)
    handle.dispose()
  })
})
