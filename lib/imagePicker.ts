import { isNativePlatform } from "./nativePlatform"

/**
 * Centralized native image selection (Phase 2A / 2B).
 *
 * On the native iOS shell, image <input type="file"> elements are intercepted
 * and replaced with a true native UIAlertController action sheet via
 * @capacitor/action-sheet, then the Camera plugin for capture / library.
 * The selected photo is converted to a standard File and delivered through
 * the input's normal `change` event so every existing upload pipeline works
 * unchanged.
 *
 * Capacitor Camera / Action Sheet are dynamic-imported only when picking,
 * so they are not part of the cold-start JS graph.
 *
 * On the web this module is a no-op; the browser file picker is untouched.
 */

async function captureNativePhoto(
  source: "CAMERA" | "PHOTOS"
): Promise<File | null> {
  try {
    const { Camera, CameraResultType, CameraSource } = await import(
      "@capacitor/camera"
    )
    const cameraSource =
      source === "CAMERA" ? CameraSource.Camera : CameraSource.Photos
    const photo = await Camera.getPhoto({
      source: cameraSource,
      // Base64 instead of Uri: the hosted WebView loads from our server
      // origin, so Capacitor's _capacitor_file_ URLs are not fetchable.
      resultType: CameraResultType.Base64,
      quality: 90,
      correctOrientation: true,
    })
    if (!photo.base64String) return null
    const format = photo.format || "jpeg"
    const mime = `image/${format}`
    const blob = await (
      await fetch(`data:${mime};base64,${photo.base64String}`)
    ).blob()
    return new File([blob], `photo-${Date.now()}.${format}`, { type: mime })
  } catch {
    // User cancelled camera/library or denied permission.
    return null
  }
}

/**
 * Present a native iOS action sheet (Take Photo / Choose From Library /
 * Cancel) and return the chosen image as a File, or null if cancelled.
 */
export async function pickImage(): Promise<File | null> {
  if (!isNativePlatform()) return null

  let index: number
  try {
    const { ActionSheet, ActionSheetButtonStyle } = await import(
      "@capacitor/action-sheet"
    )
    const result = await ActionSheet.showActions({
      title: "Add Photo",
      options: [
        { title: "📷 Take Photo" },
        { title: "🖼 Choose From Library" },
        { title: "Cancel", style: ActionSheetButtonStyle.Cancel },
      ],
    })
    index = result.index
  } catch {
    // Dismissed by tapping outside / system cancel.
    return null
  }

  if (index === 0) return captureNativePhoto("CAMERA")
  if (index === 1) return captureNativePhoto("PHOTOS")
  return null
}

function isSingleImageFileInput(
  target: EventTarget | null
): target is HTMLInputElement {
  return (
    target instanceof HTMLInputElement &&
    target.type === "file" &&
    !target.multiple &&
    /image/i.test(target.accept || "")
  )
}

/**
 * Intercept clicks on single-image file inputs (capture phase, so it runs
 * before the OS file dialog opens) and route them to the native picker.
 * The picked File is injected into the input and a bubbling `change` event
 * is dispatched, which React's delegated onChange handlers receive exactly
 * as if the user had used the browser picker.
 *
 * CSV, video, and multi-select inputs are ignored and keep WebKit's default
 * behavior. Returns a cleanup function.
 */
export function installNativeImagePicker(): () => void {
  const onClick = (event: MouseEvent) => {
    const input = event.target
    if (!isSingleImageFileInput(input)) return
    event.preventDefault()

    void (async () => {
      const file = await pickImage()
      if (!file) return
      const transfer = new DataTransfer()
      transfer.items.add(file)
      input.files = transfer.files
      // Change handlers read input.files; re-picks always re-dispatch, so the
      // "same file selected twice" browser quirk does not apply here.
      input.dispatchEvent(new Event("change", { bubbles: true }))
    })()
  }

  document.addEventListener("click", onClick, true)
  return () => document.removeEventListener("click", onClick, true)
}
