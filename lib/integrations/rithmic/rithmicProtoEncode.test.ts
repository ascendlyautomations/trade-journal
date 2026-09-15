import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  encodeMessage,
  decodeMessage,
  loadRithmicProtoTypes,
  normalizePayloadForProtobufType,
  RithmicProtoEncodeError,
} from "./rithmicProtoLoader.ts"
import { RithmicInfraType, RithmicTemplateId } from "./rithmicTemplates.ts"

describe("Rithmic Phase 1 protobuf encode", () => {
  it("RequestRithmicSystemInfo encodes templateId 16 with snake_case input", () => {
    const types = loadRithmicProtoTypes()
    const type = types.RequestRithmicSystemInfo
    const buf = encodeMessage(type, {
      template_id: RithmicTemplateId.RequestRithmicSystemInfo,
      user_msg: ["TradeTraxs", "system_info"],
    })
    assert.ok(buf.length > 0)
    const decoded = decodeMessage<{ templateId?: number; userMsg?: string[] }>(
      type,
      buf
    )
    assert.equal(decoded.templateId, 16)
    assert.deepEqual(decoded.userMsg, ["TradeTraxs", "system_info"])
  })

  it("coerces numeric string templateId to integer", () => {
    const type = loadRithmicProtoTypes().RequestRithmicSystemInfo
    const buf = encodeMessage(type, {
      templateId: "16",
      userMsg: ["x"],
    })
    const decoded = decodeMessage<{ templateId?: number }>(type, buf)
    assert.equal(decoded.templateId, 16)
  })

  it("rejects non-numeric templateId at verify boundary", () => {
    const type = loadRithmicProtoTypes().RequestRithmicSystemInfo
    assert.throws(
      () =>
        encodeMessage(type, {
          templateId: "not-a-number",
          userMsg: ["x"],
        }),
      (err: unknown) => {
        assert.ok(err instanceof RithmicProtoEncodeError)
        assert.match(err.verifyDetail, /integer expected/)
        return true
      }
    )
  })

  it("RequestLogin encodes numeric infraType and templateVersion", () => {
    const type = loadRithmicProtoTypes().RequestLogin
    const buf = encodeMessage(type, {
      templateId: RithmicTemplateId.RequestLogin,
      templateVersion: "3.9",
      userMsg: ["TradeTraxs"],
      user: "dummy_user",
      password: "dummy_password",
      appName: "TradeTraxs",
      appVersion: "1.0.0",
      systemName: "Rithmic Test",
      infraType: RithmicInfraType.ORDER_PLANT,
    })
    assert.ok(buf.length > 0)
    const decoded = decodeMessage<{ templateId?: number; infraType?: number }>(type, buf)
    assert.equal(decoded.templateId, 10)
    assert.equal(decoded.infraType, RithmicInfraType.ORDER_PLANT)
  })

  it("RequestAccountList encodes userType enum as number", () => {
    const type = loadRithmicProtoTypes().RequestAccountList
    const buf = encodeMessage(type, {
      templateId: RithmicTemplateId.RequestAccountList,
      userMsg: ["TradeTraxs"],
      fcmId: "FCM",
      ibId: "IB",
      userType: 3,
    })
    assert.ok(buf.length > 0)
  })

  it("RequestShowFillHistory encodes template 3512 with account scope", () => {
    const type = loadRithmicProtoTypes().RequestShowFillHistory
    const buf = encodeMessage(type, {
      templateId: RithmicTemplateId.RequestShowFillHistory,
      userMsg: ["TradeTraxs", "fill_history"],
      fcmId: "FCM",
      ibId: "IB",
      accountId: "ACC",
      indexFormat: "ssboe",
      startIndex: 0,
      finishIndex: 1_700_000_000,
      maxRecordCount: 10_000,
    })
    assert.ok(buf.length > 0)
    const decoded = decodeMessage<{ templateId?: number; accountId?: string }>(type, buf)
    assert.equal(decoded.templateId, 3512)
    assert.equal(decoded.accountId, "ACC")
  })

  it("normalizePayload maps official snake_case field names", () => {
    const type = loadRithmicProtoTypes().RequestHeartbeat
    const normalized = normalizePayloadForProtobufType(type, {
      template_id: 18,
    })
    assert.equal(normalized.templateId, 18)
  })
})
