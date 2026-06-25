export type SyncTextareaHeightOptions = {
  /** When set, caps growth and enables internal scroll beyond this many lines. */
  maxLines?: number
  /** When set, keeps at least this many lines visible (e.g. empty default height). */
  minLines?: number
}

export function syncTextareaHeight(
  el: HTMLTextAreaElement,
  options?: SyncTextareaHeightOptions
) {
  const style = window.getComputedStyle(el)
  const lineHeight = parseFloat(style.lineHeight) || 20
  const padding =
    parseFloat(style.paddingTop) + parseFloat(style.paddingBottom)
  const maxLines = options?.maxLines
  const minLines = options?.minLines
  const maxHeight =
    maxLines != null ? lineHeight * maxLines + padding : undefined
  const minHeight =
    minLines != null ? lineHeight * minLines + padding : undefined

  el.style.height = "0px"
  el.style.overflowY = "hidden"
  let targetHeight = el.scrollHeight

  if (minHeight != null) {
    targetHeight = Math.max(targetHeight, minHeight)
  }

  if (maxHeight != null && targetHeight > maxHeight) {
    el.style.height = `${maxHeight}px`
    el.style.overflowY = "auto"
  } else {
    el.style.height = `${targetHeight}px`
  }
}
