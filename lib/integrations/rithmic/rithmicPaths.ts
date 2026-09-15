import fs from "fs"
import path from "path"

const PACKAGE_VERSION = "0.89.0.0"

export function rithmicPackageRoot(): string {
  return path.join(process.cwd(), "third_party", "rithmic", PACKAGE_VERSION)
}

export function rithmicProtoFilePaths(): string[] {
  const protoRoot = path.join(rithmicPackageRoot(), "proto")
  const baseProto = path.join(rithmicPackageRoot(), "samples", "samples.py", "base.proto")
  return [
    baseProto,
    path.join(protoRoot, "request_rithmic_system_info.proto"),
    path.join(protoRoot, "response_rithmic_system_info.proto"),
    path.join(protoRoot, "request_login.proto"),
    path.join(protoRoot, "response_login.proto"),
    path.join(protoRoot, "request_login_info.proto"),
    path.join(protoRoot, "response_login_info.proto"),
    path.join(protoRoot, "request_account_list.proto"),
    path.join(protoRoot, "response_account_list.proto"),
    path.join(protoRoot, "request_logout.proto"),
    path.join(protoRoot, "request_heartbeat.proto"),
    path.join(protoRoot, "response_heartbeat.proto"),
    path.join(protoRoot, "request_show_fill_history.proto"),
    path.join(protoRoot, "response_show_fill_history.proto"),
  ]
}

export function defaultRithmicSslCaPath(): string {
  return path.join(process.cwd(), "lib", "integrations", "rithmic", "rithmic_ssl_cert_auth_params")
}

export type RithmicRuntimeAssetsStatus = {
  protoBundlePresent: boolean
  sslCaPresent: boolean
  missingProtoCount: number
}

export function verifyRithmicRuntimeAssets(sslCaPath: string): RithmicRuntimeAssetsStatus {
  const protoFiles = rithmicProtoFilePaths()
  const missing = protoFiles.filter((f) => !fs.existsSync(f))
  return {
    protoBundlePresent: missing.length === 0,
    sslCaPresent: fs.existsSync(sslCaPath),
    missingProtoCount: missing.length,
  }
}
