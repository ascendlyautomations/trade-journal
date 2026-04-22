export async function compressImage(file: File): Promise<File> {
  if (!file.type?.startsWith("image/")) return file

  const img = document.createElement("img")
  const canvas = document.createElement("canvas")
  const ctx = canvas.getContext("2d")

  if (!ctx) return file

  const objectUrl = URL.createObjectURL(file)

  return new Promise((resolve) => {
    img.onload = () => {
      URL.revokeObjectURL(objectUrl)

      const MAX_WIDTH = 1200

      let width = img.width
      let height = img.height

      if (width > MAX_WIDTH) {
        const scale = MAX_WIDTH / width
        width = MAX_WIDTH
        height = height * scale
      }

      canvas.width = width
      canvas.height = height

      ctx.drawImage(img, 0, 0, width, height)

      canvas.toBlob(
        (blob) => {
          if (!blob) return resolve(file)

          const newName = file.name.replace(/\.[^/.]+$/, "") + ".webp"

          resolve(
            new File([blob], newName, {
              type: "image/webp",
            })
          )
        },
        "image/webp",
        0.92
      )
    }

    img.onerror = () => {
      URL.revokeObjectURL(objectUrl)
      resolve(file)
    }

    img.src = objectUrl
  })
}
