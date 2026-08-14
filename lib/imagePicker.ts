/**
 * Native image selection — Capacitor Camera / Action Sheet removed.
 * Browser file inputs are used on web; Swift owns camera in `native-ios/`.
 */

export async function pickImage(): Promise<File | null> {
  return null
}

/** Previously intercepted file inputs for Cap picker — now a no-op. */
export function installNativeImagePicker(): () => void {
  return () => {}
}
