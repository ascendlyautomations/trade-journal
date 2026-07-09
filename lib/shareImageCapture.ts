import {
  PERFORMANCE_SHARE_EXPORT_WIDTH,
  PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT,
  type CaptureShareCardOptions,
} from "@/lib/shareImageCaptureConstants"

import { devLog } from "./devLog"

export {
  PERFORMANCE_SHARE_EXPORT_WIDTH,
  PERFORMANCE_SHARE_EXPORT_MIN_HEIGHT,
  type CaptureShareCardOptions,
} from "@/lib/shareImageCaptureConstants"

function logCaptureTarget(
  exportId: string,
  root: HTMLElement,
  logContext?: string
) {
  const prefix = logContext ? `[${logContext}]` : "[shareImageCapture]"
  const style = getComputedStyle(root)
  devLog(`${prefix} exportId:`, exportId)
  devLog(`${prefix} document.getElementById:`, root)
  devLog(`${prefix} clientWidth:`, root.clientWidth)
  devLog(`${prefix} clientHeight:`, root.clientHeight)
  devLog(`${prefix} offsetWidth:`, root.offsetWidth)
  devLog(`${prefix} offsetHeight:`, root.offsetHeight)
  devLog(`${prefix} display:`, style.display)
  devLog(`${prefix} visibility:`, style.visibility)
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

  devLog(`[${logContext}] card element found:`, exportId)

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
    const { toPng } = await import("html-to-image")
    const dataUrl = await toPng(root, {
      width,
      height,
      pixelRatio: 2,
      cacheBust: true,
      backgroundColor: "#0b1a2a",
    })
    devLog(`[${logContext}] capture success`, { width, height })
    return dataUrl
  } catch (error) {
    console.error(`[${logContext}] capture failure:`, error)
    throw error
  }
}
