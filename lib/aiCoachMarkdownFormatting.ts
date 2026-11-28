/** Shared markdown readability rules for TradeTraxs AI coaches (server prompts). */
export const AI_COACH_MARKDOWN_FORMATTING = `Readable output (use Markdown when the reply is substantive):
- Start with a concise direct answer before any detail.
- Organize longer analysis with ## headings that describe the topic (no fixed Summary / Strengths / Areas for Improvement template).
- Use numbered lists (1. 2. 3.) for improvement priorities; use "-" bullets for supporting observations.
- Bold (**text**) important statistics, findings, and actionable recommendations.
- Put a blank line between paragraphs and before each heading.
- End improvement-focused replies with one sentence naming the specific focus for the next session or trade.
- Short conversational follow-ups: natural prose or tight bullets only; do not force section headings.`