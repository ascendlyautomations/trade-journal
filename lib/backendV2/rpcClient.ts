/**
 * Generic Backend V2 RPC client.
 * Phase 1: not used by screens. Transport is injectable for tests.
 */

import {
  measureAsync,
  measureSync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"
import { isBackendV2RpcName, type BackendV2RpcName } from "./versioning.ts"

export class BackendV2RpcError extends Error {
  readonly code: string
  readonly rpcName: string
  readonly causeError: unknown

  constructor(
    code: string,
    message: string,
    rpcName: string,
    causeError?: unknown
  ) {
    super(message)
    this.name = "BackendV2RpcError"
    this.code = code
    this.rpcName = rpcName
    this.causeError = causeError
  }
}

export type BackendV2RpcTransportResult = {
  data: unknown
  error: { message?: string; code?: string } | null
}

export type BackendV2RpcTransport = {
  /**
   * Invoke a Postgres RPC. Auth is the responsibility of the transport
   * (e.g. supabase-js session). Cancellation via AbortSignal when supported.
   */
  rpc(
    name: string,
    args: Record<string, unknown> | undefined,
    signal?: AbortSignal
  ): Promise<BackendV2RpcTransportResult>
}

export type BackendV2RpcCallOptions = {
  args?: Record<string, unknown>
  signal?: AbortSignal
  /** Optional cache outcome for telemetry (callers supply; client does not cache). */
  cacheHit?: boolean
  cacheMiss?: boolean
  flagName?: string | null
}

export type BackendV2RpcClientOptions = {
  transport: BackendV2RpcTransport
  /** When true, reject unknown rpc_v1_* names. Default true. */
  enforceKnownNames?: boolean
}

export class BackendV2RpcClient {
  private readonly transport: BackendV2RpcTransport
  private readonly enforceKnownNames: boolean

  constructor(options: BackendV2RpcClientOptions) {
    this.transport = options.transport
    this.enforceKnownNames = options.enforceKnownNames !== false
  }

  async call<T>(
    rpcName: string,
    decode: (raw: unknown) => T,
    options: BackendV2RpcCallOptions = {}
  ): Promise<T> {
    if (options.signal?.aborted) {
      throw new BackendV2RpcError(
        "cancelled",
        "RPC cancelled before start",
        rpcName
      )
    }

    if (this.enforceKnownNames && !isBackendV2RpcName(rpcName)) {
      throw new BackendV2RpcError(
        "validation",
        `Unknown Backend V2 RPC name: ${rpcName}`,
        rpcName
      )
    }

    let payloadBytes: number | null = null
    let decodeMs: number | null = null
    let success = false
    let errorCode: string | null = null

    const { value: result, ms: executionMs } = await measureAsync(async () => {
      try {
        const transportResult = await this.transport.rpc(
          rpcName,
          options.args,
          options.signal
        )
        if (transportResult.error) {
          errorCode = transportResult.error.code ?? "rpc_error"
          throw new BackendV2RpcError(
            errorCode,
            transportResult.error.message ?? "RPC failed",
            rpcName,
            transportResult.error
          )
        }
        try {
          payloadBytes = utf8ByteLength(JSON.stringify(transportResult.data))
        } catch {
          payloadBytes = null
        }
        const decoded = measureSync(() => decode(transportResult.data))
        decodeMs = decoded.ms
        success = true
        return decoded.value
      } catch (err) {
        if (err instanceof BackendV2RpcError) {
          errorCode = err.code
          throw err
        }
        if (options.signal?.aborted) {
          errorCode = "cancelled"
          throw new BackendV2RpcError("cancelled", "RPC cancelled", rpcName, err)
        }
        errorCode = "unknown"
        throw new BackendV2RpcError(
          "unknown",
          err instanceof Error ? err.message : "RPC failed",
          rpcName,
          err
        )
      }
    })

    recordBackendV2Telemetry({
      rpcName,
      success,
      executionMs,
      decodeMs,
      payloadBytes,
      cacheHit: options.cacheHit ?? null,
      cacheMiss: options.cacheMiss ?? null,
      errorCode,
      flagName: options.flagName ?? null,
    })

    return result
  }

  /** Typed helper when the name is a known Backend V2 RPC. */
  async callKnown<T>(
    rpcName: BackendV2RpcName,
    decode: (raw: unknown) => T,
    options?: BackendV2RpcCallOptions
  ): Promise<T> {
    return this.call(rpcName, decode, options)
  }
}

/**
 * Creates a transport over a supabase-js-like client.
 * Session bootstrap network dedupe is applied on the shared Supabase client
 * via ensureSupabaseSessionRpcSingleFlight (not here — avoids nested-gate deadlock).
 */
import type { AppSupabaseClient } from "../supabaseTypes.ts"
import type { Database, Json } from "../database.types.ts"

/** Dynamic public RPC dispatch — Postgres validates args; decoders validate Json responses. */
async function callPublicRpc(
  client: AppSupabaseClient,
  name: string,
  args: Record<string, unknown> | undefined
): Promise<{ data: Json; error: { message?: string; code?: string } | null }> {
  const fn = name as keyof Database["public"]["Functions"]
  const response = await client.rpc(
    fn,
    (args ?? {}) as Database["public"]["Functions"][typeof fn]["Args"]
  )
  return {
    data: response.data as Json,
    error: response.error
      ? { message: response.error.message, code: response.error.code }
      : null,
  }
}

export function createSupabaseBackendV2Transport(
  client: AppSupabaseClient
): BackendV2RpcTransport {
  return {
    async rpc(name, args, signal) {
      if (signal?.aborted) {
        return {
          data: null,
          error: { code: "cancelled", message: "Aborted" },
        }
      }
      const result = await callPublicRpc(client, name, args)
      if (signal?.aborted) {
        return {
          data: null,
          error: { code: "cancelled", message: "Aborted" },
        }
      }
      return {
        data: result.data,
        error: result.error
          ? {
              message: result.error.message,
              code: result.error.code,
            }
          : null,
      }
    },
  }
}
