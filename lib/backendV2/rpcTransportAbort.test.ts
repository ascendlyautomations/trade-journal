import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { AppSupabaseClient } from "../supabaseTypes.ts"
import { createSupabaseBackendV2Transport } from "./rpcClient.ts"

function rpcClient(onAbort: (signal: AbortSignal | undefined) => void) {
  return {
    rpc(_name: string, _args: unknown) {
      return {
        abortSignal(signal: AbortSignal) {
          onAbort(signal)
          return Promise.resolve({ data: { ok: true }, error: null })
        },
      }
    },
  } as unknown as AppSupabaseClient
}

describe("createSupabaseBackendV2Transport abort", () => {
  it("forwards AbortSignal into supabase-js abortSignal()", async () => {
    let seen: AbortSignal | undefined
    const transport = createSupabaseBackendV2Transport(
      rpcClient((signal) => {
        seen = signal
      })
    )
    const controller = new AbortController()
    const result = await transport.rpc(
      "rpc_v1_feed_bootstrap",
      { p_scope: "global" },
      controller.signal
    )
    assert.equal(seen, controller.signal)
    assert.equal(result.error, null)
    assert.deepEqual(result.data, { ok: true })
  })

  it("does not call abortSignal when no signal is supplied", async () => {
    let abortCalled = false
    const transport = createSupabaseBackendV2Transport({
      rpc() {
        return {
          abortSignal() {
            abortCalled = true
            return Promise.resolve({ data: null, error: null })
          },
          then(
            resolve: (value: { data: unknown; error: null }) => void
          ) {
            resolve({ data: { ok: true }, error: null })
          },
        }
      },
    } as unknown as AppSupabaseClient)
    const result = await transport.rpc("rpc_v1_feed_bootstrap", {})
    assert.equal(abortCalled, false)
    assert.deepEqual(result.data, { ok: true })
  })

  it("aborts the in-flight RPC when the signal fires", async () => {
    const controller = new AbortController()
    const transport = createSupabaseBackendV2Transport({
      rpc() {
        return {
          abortSignal(signal: AbortSignal) {
            return new Promise((resolve) => {
              signal.addEventListener("abort", () => {
                resolve({
                  data: null,
                  error: { message: "AbortError: The user aborted a request." },
                })
              })
            })
          },
        }
      },
    } as unknown as AppSupabaseClient)

    const pending = transport.rpc(
      "rpc_v1_feed_bootstrap",
      { p_scope: "global" },
      controller.signal
    )
    controller.abort()
    const result = await pending
    assert.equal(result.error?.code, "cancelled")
    assert.equal(result.data, null)
  })
})
