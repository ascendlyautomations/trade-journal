"use client"

import Image from "next/image"
import { LANDING_FLAGSHIPS } from "@/lib/landingFlagships"
import {
  LANDING_EYEBROW,
  LANDING_HEADLINE_SM,
  LANDING_LEAD,
  LANDING_REVEAL_FROM,
  LANDING_REVEAL_TO,
  LANDING_REVEAL_TRANSITION,
  LANDING_SECTION_BORDER,
  LANDING_SECTION_SHELL,
  LANDING_SECTION_SPACING,
  useLandingReveal,
} from "@/lib/landingPageUi"

export default function LandingFlagshipSection() {
  const { ref, visible } = useLandingReveal()

  return (
    <section
      ref={ref}
      id="flagships"
      className={`${LANDING_SECTION_BORDER} ${LANDING_SECTION_SPACING}`}
      aria-labelledby="flagships-heading"
    >
      <div className={LANDING_SECTION_SHELL}>
        <div
          className={`mx-auto max-w-3xl text-center ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
        >
          <p className={LANDING_EYEBROW}>The ecosystem</p>
          <h2 id="flagships-heading" className={`${LANDING_HEADLINE_SM} mt-4`}>
            Six experiences. One platform.
          </h2>
          <p className={`${LANDING_LEAD} mx-auto mt-5`}>
            Everything traders use today, connected in one home.
          </p>
        </div>

        <div className="mt-16 space-y-20 md:mt-20 md:space-y-28 lg:space-y-32">
          {LANDING_FLAGSHIPS.map((flagship, i) => {
            const imageFirst = i % 2 === 1
            return (
              <article
                key={flagship.id}
                className={`grid items-center gap-8 lg:grid-cols-2 lg:gap-14 ${LANDING_REVEAL_TRANSITION} transition-all duration-500 ${visible ? LANDING_REVEAL_TO : LANDING_REVEAL_FROM}`}
                style={{ transitionDelay: visible ? `${i * 50}ms` : "0ms" }}
              >
                <div className={imageFirst ? "lg:order-2" : undefined}>
                  <h3 className="text-2xl font-semibold tracking-tight text-white md:text-3xl lg:text-4xl">
                    {flagship.title}
                  </h3>
                  <p className="mt-3 text-lg text-zinc-400 md:text-xl">{flagship.tagline}</p>
                </div>

                <figure
                  className={`overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.02] p-2 shadow-2xl shadow-black/50 md:p-3 ${imageFirst ? "lg:order-1" : undefined}`}
                >
                  <div className="relative aspect-[16/10] w-full overflow-hidden rounded-xl md:aspect-[16/9]">
                    <Image
                      src={flagship.imageSrc}
                      alt={flagship.imageAlt}
                      fill
                      className="object-cover object-top"
                      sizes="(max-width: 1024px) 100vw, 560px"
                      loading={i < 2 ? "eager" : "lazy"}
                    />
                  </div>
                </figure>
              </article>
            )
          })}
        </div>
      </div>
    </section>
  )
}
