/**
 * TradeTraxs AI copy style — user-facing LLM prose only.
 *
 * AI COPY STYLE:
 * - Never use em dashes (—).
 * - Use commas instead.
 * - All user-facing AI-generated prose must pass through this normalizer
 *   before being returned or displayed.
 *
 * Do not use on user-authored content, identifiers, URLs, or structured payloads.
 */

const EM_DASH = "\u2014"

/** Normalize AI-generated prose for display and API responses. */
export function normalizeAIGeneratedText(text: string): string {
  if (!text || !text.includes(EM_DASH)) {
    return text
  }

  let result = text
  result = result.replace(/ — /g, ", ")
  result = result.replace(/— /g, ", ")
  result = result.replace(/ —/g, ", ")
  result = result.replace(/(\S)—(\S)/g, "$1, $2")
  result = result.replace(/—/g, ", ")

  result = result.replace(/\s+,/g, ",")
  result = result.replace(/,{2,}/g, ", ")
  result = result.replace(/,\s{2,}/g, ", ")
  result = result.replace(/,\s*,/g, ", ")

  return result
}

/** Apply {@link normalizeAIGeneratedText} when content is present. */
export function normalizeAIProseResponse(
  text: string | null | undefined
): string | null | undefined {
  if (text == null || text === "") {
    return text
  }
  return normalizeAIGeneratedText(text)
}
