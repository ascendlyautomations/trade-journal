"use client"

import {
  useCallback,
  useLayoutEffect,
  useRef,
  useState,
  type KeyboardEvent,
  type MouseEvent,
} from "react"
import { cn } from "@/app/components/ui/cn"

export type ExpandableTextProps = {
  children: string
  /** Optional prefix label rendered before the text (e.g. "Public Description:"). */
  label?: string
  labelClassName?: string
  collapsedLines?: number
  className?: string
  textClassName?: string
  toggleClassName?: string
  /** When true, the toggle click does not bubble (for clickable card shells). */
  stopPropagation?: boolean
}

const DEFAULT_TOGGLE =
  "inline cursor-pointer border-0 bg-transparent p-0 text-inherit font-normal text-sky-400/90 hover:text-sky-300 hover:underline focus:outline-none focus-visible:underline"

function ExpandableTextContent({
  text,
  collapsedLines,
  textClassName,
  toggleClassName,
  stopPropagation,
  inline,
}: {
  text: string
  collapsedLines: number
  textClassName: string
  toggleClassName: string
  stopPropagation: boolean
  inline: boolean
}) {
  const contentRef = useRef<HTMLSpanElement>(null)
  const [expanded, setExpanded] = useState(false)
  const [canExpand, setCanExpand] = useState(false)
  const [collapsedHeight, setCollapsedHeight] = useState(0)
  const [fullHeight, setFullHeight] = useState(0)

  const measure = useCallback(() => {
    const el = contentRef.current
    if (!el) return

    const saved = {
      maxHeight: el.style.maxHeight,
      overflow: el.style.overflow,
      display: el.style.display,
      webkitLineClamp: el.style.webkitLineClamp,
      webkitBoxOrient: el.style.webkitBoxOrient,
    }

    el.style.maxHeight = "none"
    el.style.overflow = "visible"
    el.style.display = "block"
    el.style.webkitLineClamp = "unset"
    el.style.webkitBoxOrient = "unset"
    const full = el.scrollHeight

    el.style.display = "-webkit-box"
    el.style.webkitBoxOrient = "vertical"
    el.style.overflow = "hidden"
    el.style.webkitLineClamp = String(collapsedLines)
    const collapsed = el.clientHeight

    el.style.maxHeight = saved.maxHeight
    el.style.overflow = saved.overflow
    el.style.display = saved.display
    el.style.webkitLineClamp = saved.webkitLineClamp
    el.style.webkitBoxOrient = saved.webkitBoxOrient

    setFullHeight(full)
    setCollapsedHeight(collapsed)
    setCanExpand(full > collapsed + 1)
  }, [collapsedLines, text])

  useLayoutEffect(() => {
    measure()
    const el = contentRef.current
    if (!el) return

    const ro = new ResizeObserver(() => measure())
    ro.observe(el)
    return () => ro.disconnect()
  }, [measure, text])

  useLayoutEffect(() => {
    if (!canExpand && expanded) setExpanded(false)
  }, [canExpand, expanded])

  const handleToggle = (event: MouseEvent<HTMLSpanElement>) => {
    if (stopPropagation) event.stopPropagation()
    setExpanded((value) => !value)
  }

  const handleToggleKeyDown = (event: KeyboardEvent<HTMLSpanElement>) => {
    if (event.key !== "Enter" && event.key !== " ") return
    event.preventDefault()
    if (stopPropagation) event.stopPropagation()
    setExpanded((value) => !value)
  }

  const toggleInteractiveProps = stopPropagation
    ? {}
    : ({
        role: "button" as const,
        tabIndex: 0,
        onKeyDown: handleToggleKeyDown,
      } as const)

  const animatedHeight =
    canExpand && collapsedHeight > 0
      ? expanded
        ? fullHeight
        : collapsedHeight
      : undefined

  return (
    <span className={inline ? "inline" : "block"}>
      <span
        ref={contentRef}
        className={cn(
          "whitespace-pre-wrap break-words",
          inline ? "inline-block max-w-full align-top" : "block",
          textClassName
        )}
        style={
          animatedHeight != null
            ? {
                maxHeight: animatedHeight,
                overflow: "hidden",
                transition: "max-height 0.3s ease-in-out",
              }
            : undefined
        }
      >
        {text}
      </span>
      {canExpand ? (
        <>
          {" "}
          <span
            {...toggleInteractiveProps}
            onClick={handleToggle}
            className={cn(DEFAULT_TOGGLE, toggleClassName)}
            aria-expanded={expanded}
          >
            {expanded ? "Less" : "More..."}
          </span>
        </>
      ) : null}
    </span>
  )
}

export default function ExpandableText({
  children,
  label,
  labelClassName = "text-gray-400",
  collapsedLines = 3,
  className,
  textClassName = "",
  toggleClassName,
  stopPropagation = false,
}: ExpandableTextProps) {
  const text = String(children ?? "").trim()
  if (!text) return null

  const content = (
    <ExpandableTextContent
      text={text}
      collapsedLines={collapsedLines}
      textClassName={textClassName}
      toggleClassName={toggleClassName ?? ""}
      stopPropagation={stopPropagation}
      inline={Boolean(label)}
    />
  )

  if (label) {
    return (
      <p className={className}>
        <span className={labelClassName}>{label}</span> {content}
      </p>
    )
  }

  return <div className={className}>{content}</div>
}
