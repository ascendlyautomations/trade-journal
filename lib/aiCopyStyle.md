# TradeTraxs AI copy style

Permanent convention for all **AI-generated**, user-facing prose in TradeTraxs (web, iOS, BFF).

## Rules

- **Never use em dashes (`—`).** Use commas instead.
- Run every LLM reply through `normalizeAIGeneratedText()` in `lib/normalizeAIGeneratedText.ts` before returning or displaying it.
- Add the same rule to shared/system prompts so models emit fewer em dashes; **normalization remains the final safeguard**.

## Scope

**Apply normalization to:**

- Trade AI Analyst replies
- Psychology Coach / report AI summaries
- Any future feature using the shared OpenAI BFF routes

**Do not apply to:**

- User-written posts, trade descriptions, comments, DMs
- Usernames, URLs, filenames, broker imports, code
- Structured JSON extraction payloads (unless a specific string field is AI prose)

## Implementation

- **Server:** `normalizeAIProseResponse()` at AI route boundaries (`/api/analyze-trade`, `/api/psychology-coach`, …).
- **iOS:** `AIGeneratedTextNormalizer` at `DefaultAIRepository` for incoming AI replies (defense in depth).
