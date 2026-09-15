import protobuf from "protobufjs"
import { rithmicProtoFilePaths } from "@/lib/integrations/rithmic/rithmicPaths"

export type RithmicProtoTypes = {
  RequestRithmicSystemInfo: protobuf.Type
  ResponseRithmicSystemInfo: protobuf.Type
  RequestLogin: protobuf.Type
  ResponseLogin: protobuf.Type
  RequestLoginInfo: protobuf.Type
  ResponseLoginInfo: protobuf.Type
  RequestAccountList: protobuf.Type
  ResponseAccountList: protobuf.Type
  RequestLogout: protobuf.Type
  RequestHeartbeat: protobuf.Type
  RequestShowFillHistory: protobuf.Type
  ResponseShowFillHistory: protobuf.Type
  Base: protobuf.Type
}

let cached: RithmicProtoTypes | null = null

export class RithmicProtoEncodeError extends Error {
  readonly code = "rithmic_proto_encode_failed" as const
  readonly messageTypeName: string
  readonly verifyDetail: string

  constructor(messageTypeName: string, verifyDetail: string) {
    super(`rithmic_proto_encode_failed:${messageTypeName}:${verifyDetail}`)
    this.name = "RithmicProtoEncodeError"
    this.messageTypeName = messageTypeName
    this.verifyDetail = verifyDetail
  }
}

export function loadRithmicProtoTypes(): RithmicProtoTypes {
  if (cached) return cached

  let root: protobuf.Root
  try {
    root = protobuf.loadSync(rithmicProtoFilePaths())
  } catch (err) {
    const detail = err instanceof Error ? err.message : "unknown"
    throw new Error(`runtime_proto_load_failed:${detail.slice(0, 200)}`)
  }

  const type = (name: string): protobuf.Type => {
    const t = root.lookupType(`rti.${name}`)
    if (!t) throw new Error(`rithmic_proto_type_missing:${name}`)
    return t
  }

  cached = {
    RequestRithmicSystemInfo: type("RequestRithmicSystemInfo"),
    ResponseRithmicSystemInfo: type("ResponseRithmicSystemInfo"),
    RequestLogin: type("RequestLogin"),
    ResponseLogin: type("ResponseLogin"),
    RequestLoginInfo: type("RequestLoginInfo"),
    ResponseLoginInfo: type("ResponseLoginInfo"),
    RequestAccountList: type("RequestAccountList"),
    ResponseAccountList: type("ResponseAccountList"),
    RequestLogout: type("RequestLogout"),
    RequestHeartbeat: type("RequestHeartbeat"),
    RequestShowFillHistory: type("RequestShowFillHistory"),
    ResponseShowFillHistory: type("ResponseShowFillHistory"),
    Base: type("Base"),
  }

  return cached
}

/** protobufjs exposes .proto snake_case fields as camelCase on Type.fields. */
function snakeToCamel(key: string): string {
  return key.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase())
}

function resolveProtobufFieldName(
  messageType: protobuf.Type,
  key: string
): string | null {
  if (messageType.fields[key]) return key
  const camel = snakeToCamel(key)
  if (messageType.fields[camel]) return camel
  return null
}

/**
 * Normalize authored payload keys to protobufjs camelCase field names.
 * Numeric scalars must remain numbers (not strings).
 */
export function normalizePayloadForProtobufType(
  messageType: protobuf.Type,
  payload: Record<string, unknown>
): Record<string, unknown> {
  const normalized: Record<string, unknown> = {}

  for (const [key, value] of Object.entries(payload)) {
    const fieldName = resolveProtobufFieldName(messageType, key)
    if (!fieldName) continue

    const field = messageType.fields[fieldName]!
    let nextValue = value

    if (field.repeated && Array.isArray(value)) {
      nextValue = value
    } else if (
      field.type === "int32" ||
      field.type === "int64" ||
      field.type === "uint32" ||
      field.type === "uint64" ||
      field.type === "sint32" ||
      field.type === "sint64" ||
      field.type === "enum"
    ) {
      if (typeof value === "string" && value.trim() !== "" && !Number.isNaN(Number(value))) {
        nextValue = Number(value)
      }
    }

    normalized[fieldName] = nextValue
  }

  return normalized
}

export function encodeMessage(
  messageType: protobuf.Type,
  payload: Record<string, unknown>
): Uint8Array {
  const messageTypeName = messageType.name ?? "Unknown"
  const normalized = normalizePayloadForProtobufType(messageType, payload)
  const err = messageType.verify(normalized)
  if (err) {
    throw new RithmicProtoEncodeError(messageTypeName, err)
  }
  const msg = messageType.create(normalized)
  return messageType.encode(msg).finish()
}

export function decodeMessage<T extends Record<string, unknown>>(
  messageType: protobuf.Type,
  buffer: Uint8Array
): T {
  return messageType.toObject(messageType.decode(buffer), {
    longs: String,
    enums: Number,
    bytes: String,
    defaults: true,
  }) as unknown as T
}
