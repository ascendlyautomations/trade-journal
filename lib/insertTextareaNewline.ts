export type TextareaNewlineInsert = {
  value: string
  caret: number
}

/** Insert `\n` at the textarea selection; returns the next value and caret index. */
export function computeTextareaNewlineInsert(
  value: string,
  selectionStart: number,
  selectionEnd: number
): TextareaNewlineInsert {
  const start = Math.max(0, Math.min(selectionStart, value.length))
  const end = Math.max(start, Math.min(selectionEnd, value.length))
  return {
    value: `${value.slice(0, start)}\n${value.slice(end)}`,
    caret: start + 1,
  }
}

export function applyTextareaNewlineInsert(
  el: HTMLTextAreaElement,
  value: string,
  onChange: (next: string) => void
): number {
  const { value: next, caret } = computeTextareaNewlineInsert(
    value,
    el.selectionStart ?? value.length,
    el.selectionEnd ?? value.length
  )
  onChange(next)
  return caret
}
