import { BackendV2RpcError } from "./rpcClient.ts"

const SCHEMA_CONTRACT_CODES = new Set(["42703"])
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

export function isConversationThreadSchemaContractError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (SCHEMA_CONTRACT_CODES.has(err.code)) return true
  const msg = errorText(err)
  return msg.includes("does not exist") && msg.includes("column")
}

export function isConversationThreadRpcUnavailable(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (MISSING_RPC_CODES.has(err.code)) return true
  if (isConversationThreadSchemaContractError(err)) return true
  const msg = errorText(err)
  return (
    msg.includes("rpc_v1_conversation_thread_bootstrap") &&
    (msg.includes("could not find") ||
      msg.includes("does not exist") ||
      msg.includes("function"))
  )
}

export function isConversationThreadTransientError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (isConversationThreadRpcUnavailable(err)) return false
  const code = err.code
  return (
    code.startsWith("5") ||
    code === "PGRST003" ||
    code === "57014" ||
    code === "08006" ||
    code === "08003"
  )
}

export function logConversationThreadRpcUnavailable(err: unknown): void {
  if (process.env.NODE_ENV === "production") return
  if (!(err instanceof BackendV2RpcError)) return
  console.warn(
    "[backendV2.messageThreads] rpc_v1_conversation_thread_bootstrap unavailable — legacy fallback",
    { code: err.code, message: err.message }
  )
}
