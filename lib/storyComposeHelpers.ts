import { compressImage } from "@/lib/compressImage"

/** Compress story images once so preview matches the published upload. */
export async function prepareStoryImageFile(file: File): Promise<File> {
  if (file.type?.startsWith("image/")) {
    return compressImage(file)
  }
  return file
}

export function createStoryPreviewUrl(file: File): string {
  return URL.createObjectURL(file)
}

export function revokeStoryPreviewUrl(url: string | null | undefined) {
  if (url?.startsWith("blob:")) {
    URL.revokeObjectURL(url)
  }
}
