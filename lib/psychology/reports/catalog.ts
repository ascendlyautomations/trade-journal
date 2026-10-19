import type { PsychologyReportTemplate } from "./types.ts"

export const PSYCHOLOGY_REPORT_CATALOG: ReadonlyArray<{
  template: PsychologyReportTemplate
  title: string
  subtitle: string
}> = [
  {
    template: "weekly",
    title: "Weekly Psychology Report",
    subtitle: "Check-ins, discipline, emotions, and behavior for a calendar week.",
  },
  {
    template: "monthly",
    title: "Monthly Psychology Report",
    subtitle: "Monthly trends with comparisons to the prior month.",
  },
  {
    template: "sleepPerformance",
    title: "Sleep & Performance",
    subtitle: "How sleep correlates with your results.",
  },
  {
    template: "discipline",
    title: "Discipline Report",
    subtitle: "Plan adherence and execution over recent trades.",
  },
  {
    template: "emotions",
    title: "Emotional Trading",
    subtitle: "Emotion tags and their performance impact.",
  },
  {
    template: "afterLosses",
    title: "After-Loss Behavior",
    subtitle: "How you trade after consecutive losses.",
  },
  {
    template: "mentalState",
    title: "Focus / Stress / Energy",
    subtitle: "Stress, focus, and energy patterns.",
  },
  {
    template: "tradeFrequency",
    title: "Overtrading / Trade Frequency",
    subtitle: "Trade sequencing and overtrading signals.",
  },
]

export const TRADE_REVIEW_EMOTIONS = [
  "Confident",
  "Calm",
  "Focused",
  "Fearful",
  "FOMO",
  "Overconfident",
  "Hesitant",
  "Frustrated",
] as const

export function psychologyReportTitle(template: PsychologyReportTemplate): string {
  return (
    PSYCHOLOGY_REPORT_CATALOG.find((row) => row.template === template)?.title ??
    template
  )
}

export function psychologyReportSubtitle(
  template: PsychologyReportTemplate
): string {
  return (
    PSYCHOLOGY_REPORT_CATALOG.find((row) => row.template === template)
      ?.subtitle ?? ""
  )
}

export function isPeriodicPsychologyTemplate(
  template: PsychologyReportTemplate
): boolean {
  return template === "weekly" || template === "monthly"
}

export function psychologyReportID(template: PsychologyReportTemplate, periodID: string): string {
  return `psych_${template}:${periodID}`
}

export function parsePsychologyReportID(raw: string): {
  template: PsychologyReportTemplate
  periodID: string
} | null {
  if (!raw.startsWith("psych_")) return null
  const remainder = raw.slice("psych_".length)
  const separator = remainder.indexOf(":")
  if (separator < 0) return null
  const template = remainder.slice(0, separator)
  const periodID = remainder.slice(separator + 1)
  const match = PSYCHOLOGY_REPORT_CATALOG.find((row) => row.template === template)
  if (!match || !periodID) return null
  return { template: match.template, periodID }
}
