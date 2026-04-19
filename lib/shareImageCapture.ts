import { toPng } from "html-to-image"

/** Capture a hidden export root (performance share card, etc.) as a PNG data URL. */
export async function captureShareCardElementToPng(
  exportId: string,
  options?: { warmupMs?: number }
): Promise<string> {
  const root = document.getElementById(exportId)
  if (!root) {
    throw new Error(`captureShareCardElementToPng: missing #${exportId}`)
  }

  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })
  await new Promise<void>((resolve) => {
    window.setTimeout(resolve, options?.warmupMs ?? 240)
  })

  return toPng(root, {
    pixelRatio: 2,
    cacheBust: true,
    backgroundColor: "#0b1a2a",
  })
}
