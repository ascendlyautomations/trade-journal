"use client"

import Image from "next/image"
import { useState } from "react"
import ImageLightbox from "@/app/components/ui/ImageLightbox"

type LandingShowcaseImageProps = {
  src: string
  alt: string
  objectPositionClass?: string
  size?: "standard" | "large"
}

function MagnifyIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      aria-hidden
    >
      <circle cx="8.5" cy="8.5" r="5.25" />
      <path d="M13 13l4 4" strokeLinecap="round" />
    </svg>
  )
}

export default function LandingShowcaseImage({
  src,
  alt,
  objectPositionClass = "object-center",
  size = "standard",
}: LandingShowcaseImageProps) {
  const [lightboxOpen, setLightboxOpen] = useState(false)

  return (
    <>
      <button
        type="button"
        onClick={() => setLightboxOpen(true)}
        className="group relative w-full cursor-pointer overflow-hidden rounded-2xl border border-emerald-400/20 bg-[#0a0f1c]/50 text-left shadow-lg shadow-black/25 backdrop-blur-md transition-transform duration-300 ease-out hover:scale-[1.02] motion-reduce:transition-none motion-reduce:hover:scale-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-400/50"
        aria-label={`View larger: ${alt}`}
      >
        <div className="relative aspect-[3/2] w-full">
          <Image
            src={src}
            alt={alt}
            fill
            unoptimized
            quality={100}
            className={`object-contain ${objectPositionClass}`}
            sizes={
              size === "large"
                ? "(max-width: 1280px) 100vw, 1152px"
                : "(max-width: 1024px) 100vw, 720px"
            }
            loading="lazy"
          />
        </div>

        <div className="pointer-events-none absolute inset-0 flex items-end justify-center bg-gradient-to-t from-black/35 via-transparent to-transparent pb-4 opacity-0 transition-opacity duration-300 group-hover:opacity-100 group-focus-visible:opacity-100 motion-reduce:transition-none">
          <span className="flex items-center gap-1.5 rounded-full bg-black/55 px-3 py-1.5 text-xs font-medium text-white/90 backdrop-blur-sm">
            <MagnifyIcon className="h-3.5 w-3.5" />
            Click to enlarge
          </span>
        </div>
      </button>

      <ImageLightbox
        imageUrl={lightboxOpen ? src : null}
        alt={alt}
        belowNavbar
        onClose={() => setLightboxOpen(false)}
      />
    </>
  )
}
