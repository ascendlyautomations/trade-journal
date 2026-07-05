"use client"

import { useEffect, useState } from "react"
import ReelNativeVideoThumb from "@/app/components/ReelNativeVideoThumb"

type ReelVideoFilePreviewProps = {
  file: File
  className?: string
  containerClassName?: string
}

export default function ReelVideoFilePreview({
  file,
  className = "aspect-[9/16] w-full object-cover",
  containerClassName = "mx-auto w-full max-w-[220px] overflow-hidden rounded-xl border border-white/10 bg-black/40 shadow-lg shadow-black/40",
}: ReelVideoFilePreviewProps) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null)

  useEffect(() => {
    const nextUrl = URL.createObjectURL(file)
    setObjectUrl(nextUrl)
    return () => {
      URL.revokeObjectURL(nextUrl)
    }
  }, [file])

  return (
    <div className={containerClassName}>
      {objectUrl ? (
        <ReelNativeVideoThumb src={objectUrl} className={className} />
      ) : (
        <div
          className={`${className} bg-black/60`}
          aria-hidden
        />
      )}
    </div>
  )
}
