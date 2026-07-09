type JsonLdProps = {
  data: Record<string, unknown> | Array<Record<string, unknown>>
}

/** Injects JSON-LD structured data for search engines (no visible UI). */
export default function JsonLd({ data }: JsonLdProps) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  )
}
