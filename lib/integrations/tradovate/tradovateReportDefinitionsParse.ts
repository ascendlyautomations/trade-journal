export type TradovateReportDefinitionSummary = {
  name: string
  description?: string
  params: Array<{ name: string; paramType?: string; optional?: boolean }>
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function summarizeReportDefinition(raw: unknown): TradovateReportDefinitionSummary | undefined {
  if (!raw || typeof raw !== "object") return undefined
  const row = raw as Record<string, unknown>
  const name = row.name != null ? String(row.name) : ""
  if (!name) return undefined
  const paramsRaw = asArray(row.params)
  const params = paramsRaw.map((p) => {
    const pr = p as Record<string, unknown>
    return {
      name: pr.name != null ? String(pr.name) : "",
      paramType: pr.paramType != null ? String(pr.paramType) : undefined,
      optional: pr.optional === true,
    }
  })
  return {
    name,
    description: row.description != null ? String(row.description) : undefined,
    params,
  }
}

export function extractReportDefinitionsFromResponse(
  json: unknown
): TradovateReportDefinitionSummary[] {
  let rows: unknown[] = []
  if (json && typeof json === "object") {
    const record = json as Record<string, unknown>
    if (Array.isArray(record.reports)) {
      rows = record.reports
    } else if (Array.isArray(record.reportDefinitions)) {
      rows = record.reportDefinitions
    } else if (Array.isArray(json)) {
      rows = json
    }
  }
  return rows
    .map((d) => summarizeReportDefinition(d))
    .filter((d): d is TradovateReportDefinitionSummary => Boolean(d))
}
