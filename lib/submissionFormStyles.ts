/** Shared layout/styles for Feedback, Support, and related submission surfaces. */

import { PAGE_HEADING_CENTERED_CLASS } from "@/lib/pageHeadingStyles"

export const submissionPageShell =
  "min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 md:px-6 text-white"

export const submissionPageContainer = "mx-auto w-full max-w-2xl space-y-8"

export const submissionFormCard =
  "rounded-2xl border border-white/10 bg-[#0f172a]/95 p-5 md:p-8 shadow-2xl backdrop-blur-xl"

export const submissionHistoryCard =
  "rounded-2xl border border-white/10 bg-white/5 p-5 md:p-6 backdrop-blur-sm"

export const submissionTitle = PAGE_HEADING_CENTERED_CLASS

export const submissionSubtitle = "mt-2 mb-6 text-center text-sm text-gray-300"

export const submissionLabel = "mb-2 block text-sm text-gray-300"

export const submissionInput =
  "mb-4 w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"

export const submissionSelect =
  "mb-4 flex w-full min-w-0 cursor-pointer items-center justify-between rounded-xl border border-white/10 bg-[#111827] px-4 py-3 text-left text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-400"

export const submissionTextarea =
  "mb-4 w-full resize-none rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"

export const submissionFilePicker =
  "mb-4 flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-sm text-gray-200 hover:bg-white/15"

export const submissionFileBrowse =
  "rounded bg-white px-3 py-1 text-xs font-medium text-black"

export const submissionSubmitButton =
  "w-full rounded-xl bg-blue-600 py-3 font-semibold text-white transition hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-60"

export const submissionHistoryList =
  "mt-4 divide-y divide-white/10 rounded-xl border border-white/10 bg-black/20"

export const submissionHistoryItem =
  "flex flex-col gap-1 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"

export const submissionStatusPill =
  "rounded bg-white/10 px-2 py-0.5 capitalize text-gray-200"
