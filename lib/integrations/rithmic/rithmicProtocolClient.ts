import fs from "fs"
import WebSocket from "ws"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import {
  decodeMessage,
  encodeMessage,
  loadRithmicProtoTypes,
  type RithmicProtoTypes,
} from "@/lib/integrations/rithmic/rithmicProtoLoader"
import { logRithmicDiagnostic } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import type { RithmicFillHistoryRow } from "@/lib/integrations/rithmic/rithmicFillModels"
import {
  normalizeRithmicSymbolRoot,
  rithmicExecutedAtFromSsboe,
  rithmicSideFromTransactionType,
} from "@/lib/integrations/rithmic/rithmicFillModels"
import {
  RithmicInfraType,
  RithmicTemplateId,
  RITHMIC_FILL_HISTORY_MAX_RECORD_COUNT,
} from "@/lib/integrations/rithmic/rithmicTemplates"

const DEFAULT_RECV_TIMEOUT_MS = 25_000

export type RithmicSystemInfoResult = {
  systemNames: string[]
  rpCode: string[]
}

export type RithmicLoginResult = {
  success: boolean
  rpCode: string[]
  fcmId: string | null
  ibId: string | null
  uniqueUserId: string | null
  heartbeatIntervalSec: number | null
  agreementLikely: boolean
}

export type RithmicLoginInfoResult = {
  rpCode: string[]
  fcmId: string | null
  ibId: string | null
  userType: number | null
  firstName: string | null
  lastName: string | null
}

export type RithmicDiscoveredAccountRow = {
  fcmId: string
  ibId: string
  accountId: string
  accountName: string | null
  accountCurrency: string | null
  lossLimit: string | null
  accountAutoLiquidate: string | null
  autoLiqThresholdCurrentValue: string | null
}

export class RithmicProtocolClient {
  private ws: WebSocket | null = null
  private protoTypes: RithmicProtoTypes | null = null

  constructor(private readonly config: RithmicServerConfig) {}

  private proto(): RithmicProtoTypes {
    if (!this.protoTypes) {
      this.protoTypes = loadRithmicProtoTypes()
    }
    return this.protoTypes
  }

  async connect(stageLabel: "rithmic_socket_connecting" | "login_socket_connecting"): Promise<void> {
    logRithmicDiagnostic(stageLabel, { wssHost: hostFromUrl(this.config.wssUrl) })

    const ca = fs.readFileSync(this.config.sslCaPath)
    const connectedEvent =
      stageLabel === "login_socket_connecting"
        ? "login_socket_connected"
        : "rithmic_socket_connected"

    await new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(this.config.wssUrl, {
        rejectUnauthorized: true,
        ca: [ca],
        handshakeTimeout: DEFAULT_RECV_TIMEOUT_MS,
      })

      ws.on("open", () => {
        this.ws = ws
        logRithmicDiagnostic(connectedEvent, { wssHost: hostFromUrl(this.config.wssUrl) })
        resolve()
      })
      ws.on("error", (err) => reject(err))
    })
  }

  async close(): Promise<void> {
    const ws = this.ws
    this.ws = null
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.close(1000, "TradeTraxs phase1 complete")
    }
    logRithmicDiagnostic("rithmic_socket_closed")
  }

  async requestSystemInfo(): Promise<RithmicSystemInfoResult> {
    logRithmicDiagnostic("system_info_requested")
    const buf = encodeMessage(this.proto().RequestRithmicSystemInfo, {
      templateId: RithmicTemplateId.RequestRithmicSystemInfo,
      userMsg: ["TradeTraxs", "system_info"],
    })
    logRithmicDiagnostic("system_info_encoded", { byteLength: buf.length })
    await this.send(buf)
    logRithmicDiagnostic("system_info_sent")
    const raw = await this.recv("system_info_timeout")
    const rp = decodeMessage<{
      systemName?: string[]
      rpCode?: string[]
    }>(this.proto().ResponseRithmicSystemInfo, raw)

    logRithmicDiagnostic("rithmic_system_info_received", {
      systemCount: rp.systemName?.length ?? 0,
      rpCode0: rp.rpCode?.[0] ?? null,
    })

    return {
      systemNames: rp.systemName ?? [],
      rpCode: rp.rpCode ?? [],
    }
  }

  async loginOrderPlant(systemName: string): Promise<RithmicLoginResult> {
    logRithmicDiagnostic("rithmic_login_started", {
      systemName,
      infraType: RithmicInfraType.ORDER_PLANT,
    })

    const buf = encodeMessage(this.proto().RequestLogin, {
      templateId: RithmicTemplateId.RequestLogin,
      templateVersion: this.config.templateVersion,
      userMsg: ["TradeTraxs", "login"],
      user: this.config.user,
      password: this.config.password,
      appName: this.config.appName,
      appVersion: this.config.appVersion,
      systemName: systemName,
      infraType: RithmicInfraType.ORDER_PLANT,
    })
    await this.send(buf)
    const raw = await this.recv("login_timeout")
    const rp = decodeMessage<{
      rpCode?: string[]
      fcmId?: string
      ibId?: string
      uniqueUserId?: string
      heartbeatInterval?: number
    }>(this.proto().ResponseLogin, raw)

    logRithmicDiagnostic("rithmic_login_response", {
      rpCode0: rp.rpCode?.[0] ?? null,
    })

    const rpCode = rp.rpCode ?? []
    const success = rpCode.length === 1 && rpCode[0] === "0"
    const agreementLikely = !success && rpCode.some((c) => looksLikeAgreementIssue(c, rpCode))

    if (success) {
      logRithmicDiagnostic("rithmic_login_success", {
        unique_user_id: rp.uniqueUserId ?? null,
      })
    } else if (agreementLikely) {
      logRithmicDiagnostic("rithmic_agreement_required", { rpCode0: rpCode[0] ?? null })
    } else {
      logRithmicDiagnostic("rithmic_login_failed", { rpCode0: rpCode[0] ?? null })
    }

    return {
      success,
      rpCode,
      fcmId: rp.fcmId ?? null,
      ibId: rp.ibId ?? null,
      uniqueUserId: rp.uniqueUserId ?? null,
      heartbeatIntervalSec: rp.heartbeatInterval ?? null,
      agreementLikely,
    }
  }

  async requestLoginInfo(): Promise<RithmicLoginInfoResult> {
    const buf = encodeMessage(this.proto().RequestLoginInfo, {
      templateId: RithmicTemplateId.RequestLoginInfo,
      userMsg: ["TradeTraxs", "login_info"],
    })
    await this.send(buf)
    const raw = await this.recv("login_info_timeout")
    const rp = decodeMessage<{
      rpCode?: string[]
      fcmId?: string
      ibId?: string
      userType?: number
      firstName?: string
      lastName?: string
    }>(this.proto().ResponseLoginInfo, raw)

    logRithmicDiagnostic("rithmic_login_info_received", {
      rpCode0: rp.rpCode?.[0] ?? null,
      userType: rp.userType ?? null,
    })

    return {
      rpCode: rp.rpCode ?? [],
      fcmId: rp.fcmId ?? null,
      ibId: rp.ibId ?? null,
      userType: rp.userType ?? null,
      firstName: rp.firstName ?? null,
      lastName: rp.lastName ?? null,
    }
  }

  async requestAccountList(params: {
    fcmId: string
    ibId: string
    userType: number
  }): Promise<{ accounts: RithmicDiscoveredAccountRow[]; rpCode: string[] }> {
    logRithmicDiagnostic("rithmic_account_list_requested")

    const buf = encodeMessage(this.proto().RequestAccountList, {
      templateId: RithmicTemplateId.RequestAccountList,
      userMsg: ["TradeTraxs", "account_list"],
      fcmId: params.fcmId,
      ibId: params.ibId,
      userType: params.userType,
    })
    await this.send(buf)

    const accounts: RithmicDiscoveredAccountRow[] = []
    let finalRpCode: string[] = []

    for (;;) {
      const raw = await this.recvWithHeartbeat("account_list_timeout")
      const rp = decodeMessage<{
        rqHandlerRpCode?: string[]
        rpCode?: string[]
        fcmId?: string
        ibId?: string
        accountId?: string
        accountName?: string
        accountCurrency?: string
        lossLimit?: string
        accountAutoLiquidate?: string
        autoLiqThresholdCurrentValue?: string
      }>(this.proto().ResponseAccountList, raw)

      const handlerOk =
        (rp.rqHandlerRpCode?.length ?? 0) > 0 && rp.rqHandlerRpCode?.[0] === "0"

      if (
        handlerOk &&
        rp.fcmId &&
        rp.ibId &&
        rp.accountId &&
        rp.fcmId.length > 0 &&
        rp.ibId.length > 0 &&
        rp.accountId.length > 0
      ) {
        accounts.push({
          fcmId: rp.fcmId,
          ibId: rp.ibId,
          accountId: rp.accountId,
          accountName: rp.accountName ?? null,
          accountCurrency: rp.accountCurrency ?? null,
          lossLimit: rp.lossLimit ?? null,
          accountAutoLiquidate: rp.accountAutoLiquidate ?? null,
          autoLiqThresholdCurrentValue: rp.autoLiqThresholdCurrentValue ?? null,
        })
        logRithmicDiagnostic("rithmic_account_discovered", {
          account_id: rp.accountId,
        })
      }

      if ((rp.rpCode?.length ?? 0) > 0) {
        finalRpCode = rp.rpCode ?? []
        logRithmicDiagnostic("account_list_response", {
          rpCode0: finalRpCode[0] ?? null,
          accountCount: accounts.length,
        })
        break
      }
    }

    return { accounts, rpCode: finalRpCode }
  }

  async requestShowFillHistory(params: {
    fcmId: string
    ibId: string
    accountId: string
    indexFormat: "ssboe"
    startIndex: number
    finishIndex: number
    maxRecordCount?: number
  }): Promise<{ fills: RithmicFillHistoryRow[]; rpCode: string[] }> {
    logRithmicDiagnostic("rithmic_fill_history_requested")

    const maxRecordCount = Math.min(
      params.maxRecordCount ?? RITHMIC_FILL_HISTORY_MAX_RECORD_COUNT,
      RITHMIC_FILL_HISTORY_MAX_RECORD_COUNT
    )

    const buf = encodeMessage(this.proto().RequestShowFillHistory, {
      templateId: RithmicTemplateId.RequestShowFillHistory,
      userMsg: ["TradeTraxs", "fill_history"],
      fcmId: params.fcmId,
      ibId: params.ibId,
      accountId: params.accountId,
      indexFormat: params.indexFormat,
      startIndex: params.startIndex,
      finishIndex: params.finishIndex,
      maxRecordCount,
    })
    await this.send(buf)

    const fills: RithmicFillHistoryRow[] = []
    let finalRpCode: string[] = []

    for (;;) {
      const raw = await this.recvWithHeartbeat("fill_history_timeout")
      const rp = decodeMessage<{
        rqHandlerRpCode?: string[]
        rpCode?: string[]
        fcmId?: string
        ibId?: string
        accountId?: string
        symbol?: string
        exchange?: string
        transactionType?: string
        fillId?: string
        fillPrice?: number
        price?: number
        fillSize?: string | number
        ssboe?: number
        usecs?: number
        sequenceNumber?: string
      }>(this.proto().ResponseShowFillHistory, raw)

      const handlerOk =
        (rp.rqHandlerRpCode?.length ?? 0) > 0 && rp.rqHandlerRpCode?.[0] === "0"

      if (
        handlerOk &&
        rp.fillId &&
        rp.symbol &&
        rp.exchange &&
        rp.fcmId &&
        rp.ibId &&
        rp.accountId
      ) {
        const side = rithmicSideFromTransactionType(rp.transactionType)
        const qtyRaw = rp.fillSize
        const quantity =
          typeof qtyRaw === "string" ? Number(qtyRaw) : Number(qtyRaw ?? 0)
        const price = Number(rp.fillPrice ?? rp.price ?? 0)
        const executedAt =
          rithmicExecutedAtFromSsboe(rp.ssboe ?? null, rp.usecs ?? null) ??
          new Date(0).toISOString()

        if (side && Number.isFinite(quantity) && quantity > 0 && Number.isFinite(price)) {
          fills.push({
            fillId: String(rp.fillId),
            fcmId: rp.fcmId,
            ibId: rp.ibId,
            accountId: rp.accountId,
            symbol: rp.symbol,
            exchange: rp.exchange,
            side,
            quantity,
            price,
            executedAt,
            ssboe: rp.ssboe ?? null,
            usecs: rp.usecs ?? null,
            sequenceNumber: rp.sequenceNumber ?? null,
            rawSymbol: rp.symbol,
            transactionTypeRaw: rp.transactionType ?? null,
          })
        }
      }

      if ((rp.rpCode?.length ?? 0) > 0) {
        finalRpCode = rp.rpCode ?? []
        logRithmicDiagnostic("rithmic_fill_history_response", {
          rpCode0: finalRpCode[0] ?? null,
          fillCount: fills.length,
        })
        break
      }
    }

    return { fills, rpCode: finalRpCode }
  }

  async logout(): Promise<void> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return
    const buf = encodeMessage(this.proto().RequestLogout, {
      templateId: RithmicTemplateId.RequestLogout,
      userMsg: ["TradeTraxs", "logout"],
    })
    await this.send(buf)
    logRithmicDiagnostic("rithmic_logout")
  }

  private async send(buf: Uint8Array): Promise<void> {
    const ws = this.ws
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      throw new Error("rithmic_socket_not_open")
    }
    await new Promise<void>((resolve, reject) => {
      ws.send(Buffer.from(buf), (err) => (err ? reject(err) : resolve()))
    })
  }

  private async recv(timeoutErrorCode: string, timeoutMs = DEFAULT_RECV_TIMEOUT_MS): Promise<Uint8Array> {
    const ws = this.ws
    if (!ws) throw new Error("rithmic_socket_not_open")

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        cleanup()
        reject(new Error(timeoutErrorCode))
      }, timeoutMs)

      const onMessage = (data: WebSocket.RawData) => {
        cleanup()
        const buf = data instanceof Buffer ? data : Buffer.from(data as ArrayBuffer)
        resolve(new Uint8Array(buf))
      }
      const onError = (err: Error) => {
        cleanup()
        reject(err)
      }
      const onClose = () => {
        cleanup()
        reject(new Error("rithmic_socket_closed_unexpectedly"))
      }

      const cleanup = () => {
        clearTimeout(timer)
        ws.off("message", onMessage)
        ws.off("error", onError)
        ws.off("close", onClose)
      }

      ws.once("message", onMessage)
      ws.once("error", onError)
      ws.once("close", onClose)
    })
  }

  private async recvWithHeartbeat(
    timeoutErrorCode: string,
    timeoutMs = DEFAULT_RECV_TIMEOUT_MS
  ): Promise<Uint8Array> {
    try {
      return await this.recv(timeoutErrorCode, timeoutMs)
    } catch (err) {
      if (err instanceof Error && err.message === timeoutErrorCode) {
        await this.sendHeartbeat()
        return this.recv(timeoutErrorCode, timeoutMs)
      }
      throw err
    }
  }

  private async sendHeartbeat(): Promise<void> {
    const buf = encodeMessage(this.proto().RequestHeartbeat, {
      templateId: RithmicTemplateId.RequestHeartbeat,
    })
    await this.send(buf)
  }
}

function hostFromUrl(wssUrl: string): string {
  try {
    return new URL(wssUrl).host
  } catch {
    return "unknown"
  }
}

function looksLikeAgreementIssue(code: string, all: string[]): boolean {
  const blob = all.join(" ").toLowerCase()
  if (blob.includes("agreement")) return true
  if (code.toLowerCase().includes("agreement")) return true
  return false
}

export function isLoginSuccess(rpCode: string[] | undefined): boolean {
  return rpCode?.length === 1 && rpCode[0] === "0"
}

export function isAccountListSuccess(rpCode: string[] | undefined): boolean {
  if (!rpCode || rpCode.length === 0) return false
  return rpCode[0] === "0"
}
