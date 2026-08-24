import { BackendV2RpcError } from "./rpcClient.ts"

/** PostgREST / Postgres signals the RPC exists but is structurally incompatible. */
const SCHEMA_CONTRACT_CODES = new Set(["42703"])

/** RPC missing entirely or undefined function/relation. */
const MISSING_RPC_CODES = new Set(["PGRST202", "42883", "42P01"])

function causeErrorText(err: BackendV2RpcError): string {
  const cause = err.causeError
  if (cause == null) return ""
  if (typeof cause === "string") return cause
  if (typeof cause === "object") {
    if ("details" in cause && cause.details != null) {
      return String(cause.details)
    }
    if ("message" in cause && cause.message != null) {
      return String(cause.message)
    }
  }
  return ""
}

function errorText(err: BackendV2RpcError): string {
  return `${err.message} ${causeErrorText(err)}`.toLowerCase()
}

export function isRoomBootstrapSchemaContractError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (SCHEMA_CONTRACT_CODES.has(err.code)) return true
  const msg = errorText(err)
  return msg.includes("does not exist") && msg.includes("column")
}

/** True when RPC should not be retried — use controlled legacy loader once per session. */
export function isRoomBootstrapRpcUnavailable(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (MISSING_RPC_CODES.has(err.code)) return true
  if (isRoomBootstrapSchemaContractError(err)) return true
  const msg = errorText(err)
  return (
    msg.includes("rpc_v1_room_bootstrap") &&
    (msg.includes("could not find") ||
      msg.includes("does not exist") ||
      msg.includes("function"))
  )
}

/** Transient server/network failures must not trigger legacy fan-out. */
export function isRoomBootstrapTransientError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (isRoomBootstrapRpcUnavailable(err)) return false
  const code = err.code
  return (
    code.startsWith("5") ||
    code === "PGRST003" ||
    code === "57014" ||
    code === "08006" ||
    code === "08003"
  )
}

export function logRoomBootstrapRpcUnavailable(err: unknown): void {
  if (process.env.NODE_ENV === "production") return
  if (!(err instanceof BackendV2RpcError)) return
  console.warn(
    "[backendV2.rooms] rpc_v1_room_bootstrap unavailable — legacy fallback",
    { code: err.code, message: err.message }
  )
}
