import { BackendV2RpcError } from "./rpcClient.ts"
import { BackendV2RpcNames } from "./versioning.ts"

const RPC_NAME = BackendV2RpcNames.propFirm

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

/** Internal SQL/operator failures inside an existing RPC body. */
export function isPropFirmRpcExecutionError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  const msg = errorText(err)
  if (msg.includes("operator does not exist")) return true
  if (err.code === "42804") return true
  if (err.code === "42703" && msg.includes("column")) return true
  return false
}

/** True only when the RPC function itself is absent — not when the body throws. */
export function isPropFirmRpcUnavailable(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (isPropFirmRpcExecutionError(err)) return false

  const code = err.code
  const msg = errorText(err)

  if (code === "PGRST202") return true

  if (code === "42883" || code === "42P01") {
    const namesRpc =
      msg.includes(RPC_NAME) ||
      msg.includes("rpc_v1_prop_firm_bootstrap")
    const missingFunction =
      msg.includes("function") &&
      (msg.includes("does not exist") ||
        msg.includes("could not find") ||
        msg.includes("undefined_function"))
    return namesRpc && missingFunction
  }

  if (
    msg.includes(RPC_NAME) &&
    (msg.includes("could not find the function") ||
      msg.includes("could not find function"))
  ) {
    return true
  }

  return false
}

export function isPropFirmTransientError(err: unknown): boolean {
  if (!(err instanceof BackendV2RpcError)) return false
  if (isPropFirmRpcUnavailable(err)) return false
  if (isPropFirmRpcExecutionError(err)) return false
  const code = err.code
  return (
    code.startsWith("5") ||
    code === "PGRST003" ||
    code === "57014" ||
    code === "08006" ||
    code === "08003"
  )
}

export function logPropFirmRpcUnavailable(err: unknown): void {
  if (process.env.NODE_ENV === "production") return
  if (!(err instanceof BackendV2RpcError)) return
  console.warn(
    "[backendV2.propFirm] rpc_v1_prop_firm_bootstrap unavailable — legacy fallback",
    { code: err.code, message: err.message }
  )
}
