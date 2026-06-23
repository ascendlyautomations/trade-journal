import { toPng } from "html-to-image"

/** Design canvas width — export at `pixelRatio` 2 → 1040px PNG width. */
export const PERFORMANCE_SHARE_EXPORT_WIDTH = 520

/** Minimum height if layout has not resolved before capture. */
export const PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT = 720

export type CaptureShareCardOptions = {
  /** Extra wait for Recharts/SVG layout (ms). */
  warmupMs?: number
  /** Label for console logging. */
  logContext?: string
}

function logCaptureTarget(
  exportId: string,
  root: HTMLElement,
  logContext?: string
) {
  const prefix = logContext ? `[${logContext}]` : "[shareImageCapture]"
  const style = getComputedStyle(root)
  console.log(`${prefix} exportId:`, exportId)
  console.log(`${prefix} document.getElementById:`, root)
  console.log(`${prefix} clientWidth:`, root.clientWidth)
  console.log(`${prefix} clientHeight:`, root.clientHeight)
  console.log(`${prefix} offsetWidth:`, root.offsetWidth)
  console.log(`${prefix} offsetHeight:`, root.offsetHeight)
  console.log(`${prefix} display:`, style.display)
  console.log(`${prefix} visibility:`, style.visibility)
}

function ensurePerformanceShareDimensions(root: HTMLElement): {
  width: number
  height: number
} {
  root.style.boxSizing = "border-box"
  root.style.width = `${PERFORMANCE_SHARE_EXPORT_WIDTH}px`
  root.style.minWidth = `${PERFORMANCE_SHARE_EXPORT_WIDTH}px`
  root.style.maxWidth = `${PERFORMANCE_SHARE_EXPORT_WIDTH}px`

  if (getComputedStyle(root).visibility === "hidden") {
    root.style.visibility = "visible"
  }

  void root.offsetHeight

  let height = root.offsetHeight
  if (height < 100) {
    root.style.minHeight = `${PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT}px`
    void root.offsetHeight
    height = root.offsetHeight
  }

  return {
    width: root.offsetWidth || PERFORMANCE_SHARE_EXPORT_WIDTH,
    height: height || PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT,
  }
}

/** Capture a hidden export root (performance share card, etc.) as a PNG data URL. */
export async function captureShareCardElementToPng(
  exportId: string,
  options?: CaptureShareCardOptions
): Promise<string> {
  const logContext = options?.logContext ?? "shareImageCapture"
  const root = document.getElementById(exportId)

  if (!root) {
    console.error(`[${logContext}] card element NOT found:`, exportId)
    throw new Error(`captureShareCardElementToPng: missing #${exportId}`)
  }

  console.log(`[${logContext}] card element found:`, exportId)

  await new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  })
  await new Promise<void>((resolve) => {
    window.setTimeout(resolve, options?.warmupMs ?? 480)
  })

  const { width, height } = ensurePerformanceShareDimensions(root)
  logCaptureTarget(exportId, root, logContext)

  if (width < 100 || height < 100) {
    console.error(`[${logContext}] capture aborted — element too small`, {
      width,
      height,
    })
    throw new Error(
      `captureShareCardElementToPng: export root too small (${width}x${height})`
    )
  }

  try {
    const dataUrl = await toPng(root, {
      width,
      height,
      pixelRatio: 2,
      cacheBust: true,
      backgroundColor: "#0b1a2a",
    })
    console.log(`[${logContext}] capture success`, { width, height })
    return dataUrl
  } catch (error) {
    console.error(`[${logContext}] capture failure:`, error)
    throw error
  }
}
