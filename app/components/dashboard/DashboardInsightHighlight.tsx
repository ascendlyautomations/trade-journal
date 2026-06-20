"use client"

import { type ReactNode } from "react"

const MONEY_REGEX = /-?\$[\d,]+\.\d{2}/g
const WIN_RATE_REGEX = /\d+% win rate/gi

type HighlightTone = "positive" | "negative" | "auto"

type HighlightOptions = {
  /** Highlight setup/session/symbol/direction names */
  entityPattern?: RegExp
  entityTone?: HighlightTone
  moneyTone?: HighlightTone
  winRateTone?: HighlightTone
  /** Base text color for non-highlighted segments */
  baseClass?: string
  emphasisClass?: string
}

function toneClass(
  tone: HighlightTone,
  kind: "money" | "winRate" | "entity",
  value: string,
  firstMoneySign: "positive" | "negative" | "neutral"
): string {
  const positive = "font-semibold text-green-400"
  const negative = "font-semibold text-red-400"

  if (tone === "positive") return positive
  if (tone === "negative") return negative

  if (kind === "money") {
    return value.trimStart().startsWith("-") ? negative : positive
  }

  if (kind === "winRate") {
    const pct = parseInt(value, 10)
    if (Number.isFinite(pct)) {
      return pct >= 50 ? positive : negative
    }
    return firstMoneySign === "negative" ? negative : positive
  }

  if (kind === "entity") {
    if (firstMoneySign === "negative") return negative
    if (firstMoneySign === "positive") return positive
    return "font-semibold text-gray-200"
  }

  return "text-gray-200"
}

function firstMoneySign(text: string): "positive" | "negative" | "neutral" {
  const match = text.match(MONEY_REGEX)
  if (!match?.[0]) return "neutral"
  return match[0].trimStart().startsWith("-") ? "negative" : "positive"
}

type Mark = {
  start: number
  end: number
  kind: "money" | "winRate" | "entity"
  value: string
}

function collectMarks(text: string, options: HighlightOptions): Mark[] {
  const marks: Mark[] = []
  const moneySign = firstMoneySign(text)

  if (options.entityPattern) {
    const entityMatch = options.entityPattern.exec(text)
    if (entityMatch?.[1]) {
      const value = entityMatch[1]
      const start = entityMatch.index + entityMatch[0].indexOf(value)
      marks.push({ start, end: start + value.length, kind: "entity", value })
    }
  }

  for (const match of text.matchAll(MONEY_REGEX)) {
    if (match.index == null) continue
    marks.push({
      start: match.index,
      end: match.index + match[0].length,
      kind: "money",
      value: match[0],
    })
  }

  for (const match of text.matchAll(WIN_RATE_REGEX)) {
    if (match.index == null) continue
    marks.push({
      start: match.index,
      end: match.index + match[0].length,
      kind: "winRate",
      value: match[0],
    })
  }

  marks.sort((a, b) => a.start - b.start || b.end - a.end)

  const merged: Mark[] = []
  for (const mark of marks) {
    const last = merged[merged.length - 1]
    if (last && mark.start < last.end) continue
    merged.push(mark)
  }

  return merged.map((mark) => ({
    ...mark,
    ...(mark.kind === "entity"
      ? {}
      : {}),
  }))
}

export function highlightInsightText(
  text: string,
  options: HighlightOptions = {}
): ReactNode {
  const {
    entityPattern,
    entityTone = "auto",
    moneyTone = "auto",
    winRateTone = "auto",
    baseClass = "text-gray-200",
    emphasisClass = "",
  } = options

  const moneySign = firstMoneySign(text)
  const marks = collectMarks(text, { ...options, entityPattern })
  if (marks.length === 0) {
    return <span className={baseClass}>{text}</span>
  }

  const nodes: ReactNode[] = []
  let cursor = 0

  marks.forEach((mark, index) => {
    if (mark.start > cursor) {
      nodes.push(
        <span key={`t-${index}-${cursor}`} className={baseClass}>
          {text.slice(cursor, mark.start)}
        </span>
      )
    }

    const className = [
      toneClass(
        mark.kind === "entity"
          ? entityTone
          : mark.kind === "money"
            ? moneyTone
            : winRateTone,
        mark.kind,
        mark.value,
        moneySign
      ),
      emphasisClass,
    ]
      .filter(Boolean)
      .join(" ")

    nodes.push(
      <span key={`m-${index}-${mark.start}`} className={className}>
        {mark.value}
      </span>
    )
    cursor = mark.end
  })

  if (cursor < text.length) {
    nodes.push(
      <span key={`t-tail-${cursor}`} className={baseClass}>
        {text.slice(cursor)}
      </span>
    )
  }

  return <>{nodes}</>
}

/** Performance Insights bullet — entity + money + win rate semantic colors. */
export function PerformanceInsightLine({ text }: { text: string }) {
  let entityPattern: RegExp | undefined

  if (/perform best trading/i.test(text)) {
    entityPattern = /trading (.+? session)/i
  } else if (/most profitable market/i.test(text)) {
    entityPattern = /^(.+?) is your most profitable market/i
  } else if (/more profitable going/i.test(text)) {
    entityPattern = /going (.+?) \(/i
  }

  return highlightInsightText(text, { entityPattern })
}

export function SymbolInsightLine({
  symbol,
  avgPnL,
}: {
  symbol: string
  avgPnL: number
}) {
  const moneyClass =
    avgPnL >= 0
      ? "font-semibold text-green-400"
      : "font-semibold text-red-400"
  const nameClass =
    avgPnL >= 0
      ? "font-semibold text-green-400"
      : "font-semibold text-gray-200"

  return (
    <>
      <span className={nameClass}>{symbol}</span>
      <span className="text-gray-200">
        {" "}
        is your most profitable symbol (
      </span>
      <span className={moneyClass}>{formatInsightMoney(avgPnL)} avg per trade</span>
      <span className="text-gray-200">)</span>
    </>
  )
}

export function WeekdayInsightLine({
  weekday,
  avgPnL,
}: {
  weekday: string
  avgPnL: number
}) {
  const moneyClass =
    avgPnL >= 0
      ? "font-semibold text-green-400"
      : "font-semibold text-red-400"
  const dayClass =
    avgPnL >= 0
      ? "font-semibold text-green-400"
      : "font-semibold text-gray-200"

  return (
    <>
      <span className="text-gray-200">You perform best on </span>
      <span className={dayClass}>{weekday}s</span>
      <span className="text-gray-200"> (</span>
      <span className={moneyClass}>{formatInsightMoney(avgPnL)} avg</span>
      <span className="text-gray-200">)</span>
    </>
  )
}

function formatInsightMoney(value: number) {
  const abs = Math.abs(value)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
  return value < 0 ? `-$${formatted}` : `$${formatted}`
}

/** Advanced Edge — positive emphasis on setup, money, win rate. */
export function PositiveInsightLine({ text }: { text: string }) {
  return highlightInsightText(text, {
    entityPattern: /trading (.+?) \(/i,
    entityTone: "positive",
    moneyTone: "positive",
    winRateTone: "positive",
    emphasisClass: "font-semibold",
  })
}

/** Risk Insights — negative emphasis on setup, money, win rate. */
export function NegativeInsightLine({ text }: { text: string }) {
  return highlightInsightText(text, {
    entityPattern: /trading (.+?) \(/i,
    entityTone: "negative",
    moneyTone: "negative",
    winRateTone: "negative",
    emphasisClass: "font-semibold",
  })
}

/** Behavior Warnings — full line stays yellow. */
export function WarningInsightLine({ text }: { text: string }) {
  return <span className="font-semibold text-yellow-300">{text}</span>
}
