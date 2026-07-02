"use client"

/**
 * Premium landing page atmosphere — layered navy base with extremely subtle blue lighting.
 * Opacity is intentionally low; depth should be felt, not seen.
 */
export default function LandingPageBackground() {
  return (
    <div className="pointer-events-none absolute inset-0 -z-10 overflow-hidden" aria-hidden>
      {/* Base: deep navy → midnight → dark slate */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "linear-gradient(180deg, #081425 0%, #0B172A 42%, #0A1524 68%, #070B12 100%)",
        }}
      />

      {/* Top: soft blue glow behind hero */}
      <div
        className="absolute left-1/2 top-[-8%] h-[min(85vh,720px)] w-[min(140vw,1200px)] -translate-x-1/2"
        style={{
          background:
            "radial-gradient(ellipse 70% 55% at 50% 0%, rgba(59, 130, 246, 0.055) 0%, transparent 72%)",
        }}
      />

      {/* Upper-mid: faint ambient lift between sections */}
      <div
        className="absolute left-1/2 top-[28%] h-[min(55vh,480px)] w-[min(110vw,960px)] -translate-x-1/2"
        style={{
          background:
            "radial-gradient(ellipse 65% 50% at 50% 50%, rgba(72, 130, 200, 0.028) 0%, transparent 70%)",
        }}
      />

      {/* Bottom: settle back into dark navy */}
      <div
        className="absolute inset-x-0 bottom-0 h-[45vh]"
        style={{
          background:
            "linear-gradient(0deg, #070B12 0%, rgba(7, 11, 18, 0.85) 35%, transparent 100%)",
        }}
      />
      <div
        className="absolute left-1/2 bottom-[-5%] h-[min(50vh,420px)] w-[min(100vw,800px)] -translate-x-1/2"
        style={{
          background:
            "radial-gradient(ellipse 75% 55% at 50% 100%, rgba(7, 11, 18, 0.4) 0%, transparent 68%)",
        }}
      />
    </div>
  )
}
