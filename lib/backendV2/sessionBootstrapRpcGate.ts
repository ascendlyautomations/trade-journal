/**
 * Last-line network gate for rpc_v1_session_bootstrap.
 *
 * Symbol.for is shared across duplicate module instances in the same JS agent,
 * so even if sessionBootstrapSingleFlight is loaded twice, only ONE fetch runs.
 *
 * The Promise is registered BEFORE client.rpc() is invoked.
 */

type RpcResult = {
  data: unknown
  error: { message?: string; code?: string } | null
}

type GateStore = {
  /** In-flight or settled successful network promise for session bootstrap. */
  promise: Promise<RpcResult> | null
  networkStarts: number
  reuses: number
}

const GATE_SYMBOL = Symbol.for("tradetraxs.sessionBootstrap.rpcGate")

function gateStore(): GateStore {
  const g = globalThis as typeof globalThis & {
    [GATE_SYMBOL]?: GateStore
  }
  if (!g[GATE_SYMBOL]) {
    g[GATE_SYMBOL] = { promise: null, networkStarts: 0, reuses: 0 }
  }
  return g[GATE_SYMBOL]
}

export function clearSessionBootstrapRpcGate(): void {
  const s = gateStore()
  s.promise = null
}

export function getSessionBootstrapRpcGateStats(): {
  networkStarts: number
  reuses: number
  hasPromise: boolean
} {
  const s = gateStore()
  return {
    networkStarts: s.networkStarts,
    reuses: s.reuses,
    hasPromise: s.promise != null,
  }
}

export function __resetSessionBootstrapRpcGateForTests(): void {
  const s = gateStore()
  s.promise = null
  s.networkStarts = 0
  s.reuses = 0
}

/**
 * Deduplicate the actual HTTP RPC. Call only for BackendV2RpcNames.session.
 */
export async function runSessionBootstrapRpcOnce(
  invoke: () => PromiseLike<RpcResult>
): Promise<RpcResult> {
  const s = gateStore()
  if (s.promise) {
    s.reuses += 1
    return s.promise
  }

  // Reserve BEFORE invoke() so concurrent callers join this Promise.
  let resolve!: (value: RpcResult) => void
  let reject!: (reason: unknown) => void
  const reserved = new Promise<RpcResult>((res, rej) => {
    resolve = res
    reject = rej
  })
  s.promise = reserved
  s.networkStarts += 1

  try {
    const result = await invoke()
    if (result.error) {
      // Allow retry after transport/RPC error.
      if (s.promise === reserved) s.promise = null
      resolve(result)
      return result
    }
    resolve(result)
    return result
  } catch (err) {
    if (s.promise === reserved) s.promise = null
    reject(err)
    throw err
  }
}
