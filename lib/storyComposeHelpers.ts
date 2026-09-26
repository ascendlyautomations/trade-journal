export function createStoryPreviewUrl(file: File): string {
  return URL.createObjectURL(file)
}

export function revokeStoryPreviewUrl(url: string | null | undefined) {
  if (url?.startsWith("blob:")) {
    URL.revokeObjectURL(url)
  }
}
