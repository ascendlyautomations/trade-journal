import path from "path"
import protobuf from "protobufjs"

const PROTO_ROOT = path.join(process.cwd(), "third_party/rithmic/0.89.0.0/proto")
const BASE_PROTO = path.join(
  process.cwd(),
  "third_party/rithmic/0.89.0.0/samples/samples.py/base.proto"
)

const PROTO_FILES = [
  BASE_PROTO,
  path.join(PROTO_ROOT, "request_rithmic_system_info.proto"),
  path.join(PROTO_ROOT, "response_rithmic_system_info.proto"),
  path.join(PROTO_ROOT, "request_login.proto"),
  path.join(PROTO_ROOT, "response_login.proto"),
  path.join(PROTO_ROOT, "request_login_info.proto"),
  path.join(PROTO_ROOT, "response_login_info.proto"),
  path.join(PROTO_ROOT, "request_account_list.proto"),
  path.join(PROTO_ROOT, "response_account_list.proto"),
  path.join(PROTO_ROOT, "request_logout.proto"),
  path.join(PROTO_ROOT, "request_heartbeat.proto"),
  path.join(PROTO_ROOT, "response_heartbeat.proto"),
]

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
  Base: protobuf.Type
}

let cached: RithmicProtoTypes | null = null

export function loadRithmicProtoTypes(): RithmicProtoTypes {
  if (cached) return cached

  const root = protobuf.loadSync(PROTO_FILES)

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
    Base: type("Base"),
  }

  return cached
}

export function encodeMessage(
  messageType: protobuf.Type,
  payload: Record<string, unknown>
): Uint8Array {
  const err = messageType.verify(payload)
  if (err) throw new Error(`rithmic_proto_verify:${err}`)
  const msg = messageType.create(payload)
  return messageType.encode(msg).finish()
}

export function decodeMessage<T extends Record<string, unknown>>(
  messageType: protobuf.Type,
  buffer: Uint8Array
): T {
  return messageType.decode(buffer) as unknown as T
}
