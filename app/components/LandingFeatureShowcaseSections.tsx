"use client"

import { useEffect, useRef, useState } from "react"
import { LANDING_FLAGSHIPS } from "@/lib/landingFlagships"
import LandingShowcaseImage from "@/app/components/landing/LandingShowcaseImage"
import {
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_TITLE_GRADIENT,
  useLandingReveal,
} from "@/lib/landingPageUi"

function layoutClassForIndex(index: number): string {
  return index % 2 === 1
    ? "flex-col-reverse lg:flex-row-reverse"
    : "flex-col-reverse lg:flex-row"
}

function FlagshipBlock({
  flagship,
  index,
}: {
  flagship: (typeof LANDING_FLAGSHIPS)[number]
  index: number
}) {
  const ref = useRef<HTMLElement>(null)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVisible(true)
      return
    }
    const el = ref.current
    if (!el) return
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setVisible(true)
          io.unobserve(el)
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -5% 0px" }
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  return (
    <section
      ref={ref}
      id={flagship.id}
      className={`relative z-10 scroll-mt-24 border-t border-white/10 px-6 py-16 md:py-20 lg:py-24 transition-[opacity,transform] duration-[400ms] ease-out ${LANDING_REVEAL_TRANSITION} ${
        visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM
      }`}
      aria-labelledby={`${flagship.id}-heading`}
    >
      <div className="mx-auto max-w-6xl">
        <div className={`flex gap-10 lg:items-center lg:gap-14 ${layoutClassForIndex(index)}`}>
          <div className="min-w-0 flex-1 space-y-4 text-left">
            <h3
              id={`${flagship.id}-heading`}
              className="text-3xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl"
            >
              {flagship.title}
            </h3>
            <p className="text-base leading-relaxed text-gray-400 md:text-lg">{flagship.tagline}</p>
            {flagship.bonuses ? (
              <p className="text-sm text-gray-500">{flagship.bonuses}</p>
            ) : null}
          </div>
          <div className="min-w-0 flex-1">
            <LandingShowcaseImage
              src={flagship.imageSrc}
              alt={flagship.imageAlt}
              objectPositionClass={flagship.imageObjectPosition ?? "object-center"}
            />
          </div>
        </div>
      </div>
    </section>
  )
}

export default function LandingFeatureShowcaseSections() {
  const { ref, visible } = useLandingReveal()

  return (
    <div id="grow" className="relative z-10">
      <section
        ref={ref}
        className={`border-t border-white/10 px-6 pt-20 pb-8 text-center md:pt-28 md:pb-10 ${LANDING_REVEAL_TRANSITION} ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        aria-labelledby="grow-heading"
      >
        <div className="mx-auto max-w-3xl">
          <h2 id="grow-heading" className="text-3xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl lg:text-5xl">
            Everything You Need to{" "}
            <span className={LANDING_TITLE_GRADIENT}>Grow as a Trader</span>
          </h2>
        </div>
      </section>

      {LANDING_FLAGSHIPS.map((flagship, index) => (
        <FlagshipBlock key={flagship.id} flagship={flagship} index={index} />
      ))}
    </div>
  )
}
