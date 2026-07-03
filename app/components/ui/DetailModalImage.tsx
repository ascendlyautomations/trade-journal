"use client"

import StorageImage from "@/app/components/ui/StorageImage"

type DetailModalImageProps = {
  src: string
  onClick?: (url: string) => void
}

/** Modal screenshot: stacked on mobile, fill left panel on md+. */
export default function DetailModalImage({ src, onClick }: DetailModalImageProps) {
  return (
    <StorageImage
      src={src}
      originalSrc={src}
      preset="feed-detail"
      alt=""
      className="block w-full max-h-[60dvh] cursor-pointer bg-black/30 object-contain md:max-h-full md:max-w-full md:bg-transparent"
      onClick={
        onClick
          ? (e) => {
              e.stopPropagation()
              onClick(src)
            }
          : undefined
      }
    />
  )
}
