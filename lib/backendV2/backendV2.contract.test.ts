import { describe, it, beforeEach, afterEach } from "node:test"
import { decodeSessionBootstrapV1, decodeFeedBootstrapV1, decodeDashboardBootstrapV1, decodeProfileBootstrapV1, decodeMessagesBootstrapV1, decodeRoomsBootstrapV1, decodeActivityBootstrapV1, decodeExploreBootstrapV1, decodeLeaderboardBootstrapV1, decodeCalendarBootstrapV1, decodeTradeDetailBootstrapV1, decodeSettingsBootstrapV1, } from "./contracts.ts"
import { sessionBootstrapFixture, dashboardBootstrapFixture, feedBootstrapFixture, profileBootstrapFixture, messagesBootstrapFixture, roomsBootstrapFixture, activityBootstrapFixture, exploreBootstrapFixture, leaderboardBootstrapFixture, calendarBootstrapFixture, tradeDetailBootstrapFixture, settingsBootstrapFixture, } from "./fixtures.ts"
import { BackendV2RpcClient, BackendV2RpcError } from "./rpcClient.ts"
import { BackendV2RpcNames } from "./versioning.ts"
import { isBackendV2Enabled, listBackendV2Flags, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import { __withBackendV2EnvIsolatedForTests, } from "./flags.testIsolation.ts"
import {
  setBackendV2TelemetryEnabled,
  setBackendV2TelemetrySink,
  type BackendV2TelemetryEvent,
} from "./telemetry.ts"
import {
  createUnimplementedRpcBootstrap,
  type DashboardBootstrapProviding,
} from "./adapters.ts"
import assert from "node:assert/strict"

type BootstrapDecode = (raw: unknown) => {
  meta: { contract_version: string }
  data: unknown
}

describe("Backend V2 contract decode", () => {
  const cases: Array<[string, unknown, BootstrapDecode]> = [
    ["session", sessionBootstrapFixture, decodeSessionBootstrapV1],
    ["dashboard", dashboardBootstrapFixture, decodeDashboardBootstrapV1],
    ["feed", feedBootstrapFixture, decodeFeedBootstrapV1],
    ["profile", profileBootstrapFixture, decodeProfileBootstrapV1],
    ["messages", messagesBootstrapFixture, decodeMessagesBootstrapV1],
    ["rooms", roomsBootstrapFixture, decodeRoomsBootstrapV1],
    ["activity", activityBootstrapFixture, decodeActivityBootstrapV1],
    ["explore", exploreBootstrapFixture, decodeExploreBootstrapV1],
    ["leaderboard", leaderboardBootstrapFixture, decodeLeaderboardBootstrapV1],
    ["calendar", calendarBootstrapFixture, decodeCalendarBootstrapV1],
    ["tradeDetail", tradeDetailBootstrapFixture, decodeTradeDetailBootstrapV1],
    ["settings", settingsBootstrapFixture, decodeSettingsBootstrapV1],
  ]

  for (const [name, fixture, decode] of cases) {
    it(`JSON → ${name} contract → decode`, () => {
      const json = JSON.stringify(fixture)
      const raw = JSON.parse(json)
      const decoded = decode(raw)
      assert.equal(decoded.meta.contract_version, "v1")
      assert.ok(decoded.data)
    })
  }

  it("rejects wrong contract_version", () => {
    const bad = JSON.parse(JSON.stringify(sessionBootstrapFixture))
    bad.meta.contract_version = "v0"
    assert.throws(() => decodeSessionBootstrapV1(bad), /version mismatch/)
  })

  it("rejects missing data envelope", () => {
    assert.throws(
      () => decodeSessionBootstrapV1({ meta: sessionBootstrapFixture.meta }),
      /expected \{ meta, data \}/
    )
  })
})

describe("Backend V2 feature flags", () => {
  afterEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("defaults all flags OFF", () => {
    __withBackendV2EnvIsolatedForTests(() => {
      const flags = listBackendV2Flags()
      assert.equal(flags.length, 15)
      for (const flag of flags) {
        assert.equal(flag.enabled, false, flag.name)
        assert.equal(isBackendV2Enabled(flag.key), false)
      }
    })
  })

  it("ignores developer .env.local flag values when env is isolated", () => {
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_FEED
    process.env.NEXT_PUBLIC_BACKEND_V2_FEED = "1"
    try {
      __withBackendV2EnvIsolatedForTests(() => {
        assert.equal(isBackendV2Enabled("feed"), false)
      })
    } finally {
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_FEED
      else process.env.NEXT_PUBLIC_BACKEND_V2_FEED = prev
    }
  })

  it("test override does not leak after reset", () => {
    __setBackendV2FlagForTests("feed", true)
    assert.equal(isBackendV2Enabled("feed"), true)
    __resetBackendV2FlagsForTests()
    assert.equal(isBackendV2Enabled("feed"), false)
  })
})

describe("Backend V2 RPC client", () => {
  beforeEach(() => {
    setBackendV2TelemetryEnabled(true)
  })

  afterEach(() => {
    setBackendV2TelemetrySink(null)
    setBackendV2TelemetryEnabled(false)
  })

  it("decodes typed payload and records telemetry", async () => {
    const events: BackendV2TelemetryEvent[] = []
    setBackendV2TelemetrySink((e) => events.push(e))

    const client = new BackendV2RpcClient({
      transport: {
        async rpc() {
          return { data: sessionBootstrapFixture, error: null }
        },
      },
    })

    const result = await client.callKnown(
      BackendV2RpcNames.session,
      decodeSessionBootstrapV1,
      { cacheMiss: true, flagName: "backendV2.session" }
    )

    assert.equal(result.data.viewer.username, "viewer")
    assert.equal(events.length, 1)
    assert.equal(events[0].success, true)
    assert.equal(events[0].rpcName, BackendV2RpcNames.session)
    assert.equal(events[0].cacheMiss, true)
    assert.ok(typeof events[0].executionMs === "number")
    assert.ok(typeof events[0].decodeMs === "number")
    assert.ok(typeof events[0].payloadBytes === "number")
  })

  it("rejects unknown RPC names", async () => {
    const client = new BackendV2RpcClient({
      transport: {
        async rpc() {
          return { data: null, error: null }
        },
      },
    })
    await assert.rejects(
      () => client.call("not_a_backend_v2_rpc", (x) => x),
      /Unknown Backend V2 RPC/
    )
  })

  it("maps transport errors to BackendV2RpcError", async () => {
    const client = new BackendV2RpcClient({
      transport: {
        async rpc() {
          return {
            data: null,
            error: { code: "PGRST202", message: "function missing" },
          }
        },
      },
    })
    await assert.rejects(
      () =>
        client.callKnown(BackendV2RpcNames.session, decodeSessionBootstrapV1),
      (err: unknown) => {
        assert.ok(err instanceof BackendV2RpcError)
        assert.equal(err.name, "BackendV2RpcError")
        assert.equal(err.code, "PGRST202")
        return true
      }
    )
  })

  it("supports cancellation via AbortSignal", async () => {
    const controller = new AbortController()
    controller.abort()
    const client = new BackendV2RpcClient({
      transport: {
        async rpc() {
          return { data: sessionBootstrapFixture, error: null }
        },
      },
    })
    await assert.rejects(
      () =>
        client.callKnown(BackendV2RpcNames.session, decodeSessionBootstrapV1, {
          signal: controller.signal,
        }),
      /cancelled/
    )
  })
})

describe("Backend V2 adapters", () => {
  it("unimplemented RPC stub throws", async () => {
    const stub =
      createUnimplementedRpcBootstrap<DashboardBootstrapProviding>("DashboardRpc")
    await assert.rejects(
      () => stub.loadDashboardBootstrap(),
      /not implemented yet/
    )
  })
})
export {}
