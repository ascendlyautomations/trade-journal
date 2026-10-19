"use client"

import type { ReactNode, RefObject } from "react"
import {
  STORY_TEXT_COLOR_PRESETS,
  storyTextFillCss,
  storyTextFillIsCustom,
  storyTextFillMatchesPreset,
  type StoryTextAlignment,
  type StoryTextColorPreset,
  type StoryTextFill,
  STORY_OVERLAY_SCALE_MAX,
  STORY_OVERLAY_SCALE_MIN,
  clampOverlayScale,
} from "@/lib/storyEditor/storyTextOverlay"

const STORY_TEXT_SCALE_STEP = 0.1

const PRESET_SWATCH: Record<StoryTextColorPreset, string> = {
  white: "#ffffff",
  black: "#000000",
  accentBlue: "rgb(89, 166, 255)",
  accentGreen: "rgb(89, 224, 140)",
  accentRed: "rgb(255, 89, 89)",
  accentYellow: "rgb(255, 224, 64)",
}

type StoryTextEditingChromeProps = {
  draftText: string
  selectedTextFill: StoryTextFill
  selectedAlignment: StoryTextAlignment
  showsTextBackground: boolean
  textScale: number
  onTextScaleChange: (scale: number) => void
  onDraftChange: (text: string) => void
  onSelectPreset: (preset: StoryTextColorPreset) => void
  onCustomFillChange: (fill: StoryTextFill) => void
  onAlignmentChange: (alignment: StoryTextAlignment) => void
  onBackgroundChange: (value: boolean) => void
  onDelete: () => void
  onDone: () => void
  textAreaRef?: RefObject<HTMLTextAreaElement | null>
}

export default function StoryTextEditingChrome({
  draftText,
  selectedTextFill,
  selectedAlignment,
  showsTextBackground,
  textScale,
  onTextScaleChange,
  onDraftChange,
  onSelectPreset,
  onCustomFillChange,
  onAlignmentChange,
  onBackgroundChange,
  onDelete,
  onDone,
  textAreaRef,
}: StoryTextEditingChromeProps) {
  const customSelected = storyTextFillIsCustom(selectedTextFill)
  const hexForInput = rgbToHex(selectedTextFill)

  return (
    <div
      className="space-y-3 rounded-xl border border-white/15 bg-black/25 p-3 sm:p-4"
      data-testid="story-text-editing-chrome"
    >
      <p className="text-xs font-semibold uppercase tracking-wide text-gray-300">
        Text style
      </p>
      <div className="flex flex-wrap items-center gap-2">
        {STORY_TEXT_COLOR_PRESETS.map((preset) => (
          <button
            key={preset}
            type="button"
            aria-label={`Text color ${preset}`}
            onClick={() => onSelectPreset(preset)}
            className={`h-7 w-7 rounded-full border-2 ${
              storyTextFillMatchesPreset(selectedTextFill, preset)
                ? "border-emerald-400"
                : "border-transparent"
            }`}
            style={{ backgroundColor: PRESET_SWATCH[preset] }}
          />
        ))}
        <label className="relative h-7 w-7 cursor-pointer rounded-full border-2 border-transparent ring-emerald-400 has-[:focus-visible]:ring-2">
          <span
            className={`absolute inset-0 rounded-full ${
              customSelected ? "ring-2 ring-emerald-400" : ""
            }`}
            style={{ backgroundColor: storyTextFillCss(selectedTextFill) }}
            aria-hidden
          />
          <input
            type="color"
            className="absolute inset-0 h-full w-full cursor-pointer opacity-0"
            value={hexForInput}
            onChange={(e) => {
              const rgb = hexToRgb(e.target.value)
              if (rgb) {
                onCustomFillChange({
                  ...rgb,
                  alpha: selectedTextFill.alpha,
                })
              }
            }}
            aria-label="Custom text color"
          />
        </label>
        <label className="flex items-center gap-1 text-xs text-gray-300">
          A
          <input
            type="range"
            min={0.2}
            max={1}
            step={0.05}
            value={selectedTextFill.alpha}
            onChange={(e) =>
              onCustomFillChange({
                ...selectedTextFill,
                alpha: Number(e.target.value),
              })
            }
            className="w-16"
            aria-label="Text opacity"
          />
        </label>
      </div>

      <div className="space-y-1.5">
        <div className="flex items-center justify-between gap-2">
          <span className="text-xs font-medium text-gray-300">Text size</span>
          <span className="text-xs tabular-nums text-gray-400">
            {Math.round(textScale * 100)}%
          </span>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            aria-label="Decrease text size"
            onClick={() =>
              onTextScaleChange(
                clampOverlayScale(textScale - STORY_TEXT_SCALE_STEP)
              )
            }
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-white/15 bg-white/10 text-lg font-medium text-white transition hover:bg-white/15"
          >
            −
          </button>
          <input
            type="range"
            min={STORY_OVERLAY_SCALE_MIN}
            max={STORY_OVERLAY_SCALE_MAX}
            step={STORY_TEXT_SCALE_STEP}
            value={textScale}
            onChange={(e) =>
              onTextScaleChange(clampOverlayScale(Number(e.target.value)))
            }
            className="min-w-0 flex-1 accent-emerald-400"
            aria-label="Text size"
          />
          <button
            type="button"
            aria-label="Increase text size"
            onClick={() =>
              onTextScaleChange(
                clampOverlayScale(textScale + STORY_TEXT_SCALE_STEP)
              )
            }
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-white/15 bg-white/10 text-lg font-medium text-white transition hover:bg-white/15"
          >
            +
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm text-gray-200">
        <AlignmentButton
          active={selectedAlignment === "leading"}
          label="Align left"
          onClick={() => onAlignmentChange("leading")}
        >
          ≡
        </AlignmentButton>
        <AlignmentButton
          active={selectedAlignment === "center"}
          label="Align center"
          onClick={() => onAlignmentChange("center")}
        >
          ≣
        </AlignmentButton>
        <AlignmentButton
          active={selectedAlignment === "trailing"}
          label="Align right"
          onClick={() => onAlignmentChange("trailing")}
        >
          ≡
        </AlignmentButton>
        <button
          type="button"
          aria-pressed={showsTextBackground}
          onClick={() => onBackgroundChange(!showsTextBackground)}
          className={`rounded-lg border px-2.5 py-1.5 ${
            showsTextBackground
              ? "border-emerald-400/50 bg-emerald-500/15 text-emerald-200"
              : "border-white/10 bg-white/5 text-gray-300"
          }`}
        >
          BG
        </button>
        <button
          type="button"
          onClick={onDelete}
          className="rounded-lg border border-red-500/30 bg-red-500/10 px-2.5 py-1.5 text-red-300"
        >
          Delete
        </button>
      </div>

      <textarea
        ref={textAreaRef}
        data-story-text-draft="true"
        value={draftText}
        onChange={(e) => onDraftChange(e.target.value)}
        placeholder="Type something…"
        rows={3}
        className="w-full resize-none rounded-lg border border-white/20 bg-white/10 px-3 py-2 text-sm text-white placeholder:text-gray-400"
      />

      <button
        type="button"
        onClick={onDone}
        className="w-full rounded-lg bg-emerald-500/20 py-2.5 text-sm font-semibold text-emerald-100 ring-1 ring-emerald-400/40 transition hover:bg-emerald-500/30"
      >
        Done editing text
      </button>
    </div>
  )
}

function AlignmentButton({
  active,
  label,
  onClick,
  children,
}: {
  active: boolean
  label: string
  onClick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className={`min-w-[2.25rem] rounded-lg border px-2 py-1.5 ${
        active
          ? "border-emerald-400/50 bg-emerald-500/15 font-bold text-emerald-200"
          : "border-white/10 bg-white/5 text-gray-400"
      }`}
    >
      {children}
    </button>
  )
}

function rgbToHex(fill: StoryTextFill): string {
  const r = Math.round(fill.red * 255)
  const g = Math.round(fill.green * 255)
  const b = Math.round(fill.blue * 255)
  return `#${[r, g, b].map((n) => n.toString(16).padStart(2, "0")).join("")}`
}

function hexToRgb(hex: string): Omit<StoryTextFill, "alpha"> | null {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
  if (!m) return null
  return {
    red: parseInt(m[1], 16) / 255,
    green: parseInt(m[2], 16) / 255,
    blue: parseInt(m[3], 16) / 255,
  }
}
