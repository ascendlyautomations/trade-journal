"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"

/**
 * Mount chart children only after the frame has a real box.
 * Hidden responsive charts otherwise measure as width/height -1.
 */
export default function ChartWhenSized({
  height,
  className,
  children,
}: {
  height: number
  className?: string
  children: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [sized, setSized] = useState(false)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const measure = () => {
      const rect = el.getBoundingClientRect()
      setSized(rect.width > 0 && rect.height > 0)
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  return (
    <div
      ref={ref}
      className={className}
      style={{ height, width: "100%", minWidth: 0 }}
    >
      {sized ? children : null}
    </div>
  )
}
