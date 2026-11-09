import assert from "node:assert/strict"
import { describe, it } from "node:test"

import {
  DEFAULT_TRADING_SESSION,
  getSessionFromDate,
  normalizeTradingSessionLabel,
  TRADING_SESSION_LABELS,
} from "./tradingSession.ts"

/** Fixed ET instants (noon UTC in January is not ET-safe for all cases — use explicit ISO with offset where needed). */
function etLocal(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute = 0
): Date {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  })
  const probe = new Date(Date.UTC(year, month - 1, day, 12, 0, 0))
  void formatter.format(probe)
  const pad = (n: number) => String(n).padStart(2, "0")
  const iso = `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:00`
  const guess = new Date(iso + "-05:00")
  const summer = month >= 4 && month <= 10
  return new Date(iso + (summer ? "-04:00" : "-05:00"))
}

describe("getSessionFromDate", () => {
  it("classifies NY AM, Lunch, PM boundaries in Eastern", () => {
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 8, 0)),
      TRADING_SESSION_LABELS.nyAM
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 11, 29)),
      TRADING_SESSION_LABELS.nyAM
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 11, 30)),
      TRADING_SESSION_LABELS.nyLunch
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 13, 29)),
      TRADING_SESSION_LABELS.nyLunch
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 13, 30)),
      TRADING_SESSION_LABELS.nyPM
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 16, 59)),
      TRADING_SESSION_LABELS.nyPM
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 17, 0)),
      TRADING_SESSION_LABELS.after
    )
  })

  it("preserves London and Asia", () => {
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 3, 0)),
      TRADING_SESSION_LABELS.london
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 7, 59)),
      TRADING_SESSION_LABELS.london
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 6, 10, 19, 0)),
      TRADING_SESSION_LABELS.asia
    )
    assert.equal(
      getSessionFromDate(etLocal(2026, 1, 15, 1, 0)),
      TRADING_SESSION_LABELS.asia
    )
  })
})

describe("normalizeTradingSessionLabel", () => {
  it("maps legacy NY to NY AM", () => {
    assert.equal(normalizeTradingSessionLabel("NY"), TRADING_SESSION_LABELS.nyAM)
    assert.equal(
      normalizeTradingSessionLabel("New York"),
      TRADING_SESSION_LABELS.nyAM
    )
  })

  it("default constant", () => {
    assert.equal(DEFAULT_TRADING_SESSION, TRADING_SESSION_LABELS.nyAM)
  })
})
