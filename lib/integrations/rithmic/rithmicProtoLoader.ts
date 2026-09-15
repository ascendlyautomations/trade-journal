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
  Base: protobuf.Type
}

let cached: RithmicProtoTypes | null = null

export function loadRithmicProtoTypes(): RithmicProtoTypes {
  if (cached) return cached

  const root = protobuf.loadSync(rithmicProtoFilePaths())

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
