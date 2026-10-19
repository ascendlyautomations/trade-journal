import { validateImageUpload } from "@/lib/uploadValidation"

export function createStoryPreviewUrl(file: File): string {
  return URL.createObjectURL(file)
}

export function revokeStoryPreviewUrl(url: string | null | undefined) {
  if (url?.startsWith("blob:")) {
    URL.revokeObjectURL(url)
  }
}

/** Validates and returns null, or an error message for the picker UI. */
export function validateStorySourceFile(file: File): string | null {
  return validateImageUpload(file)
}
