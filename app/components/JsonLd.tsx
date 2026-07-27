type JsonLdProps = {
  data: Record<string, unknown> | Array<Record<string, unknown> | null | undefined>
}

function isJsonLdObject(
  value: unknown
): value is Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
}

/**
 * Injects JSON-LD structured data for search engines (no visible UI).
 * Renders one script tag per object so parsers that expect a single object
 * with `@context` never see an array root or undefined entries.
 */
export default function JsonLd({ data }: JsonLdProps) {
  const items = (Array.isArray(data) ? data : [data]).filter(isJsonLdObject)

  if (items.length === 0) return null

  return (
    <>
      {items.map((item, index) => {
        const context = item["@context"]
        const safeItem =
          typeof context === "string" && context.trim().length > 0
            ? item
            : { "@context": "https://schema.org", ...item }

        return (
          <script
            key={`jsonld-${index}-${String(safeItem["@type"] ?? "node")}`}
            type="application/ld+json"
            dangerouslySetInnerHTML={{ __html: JSON.stringify(safeItem) }}
          />
        )
      })}
    </>
  )
}
