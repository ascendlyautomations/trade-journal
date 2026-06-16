"use client"

import { useCallback, useEffect, useState } from "react"
import type { FeedbackModalProps } from "./FeedbackModal"
import type { FeedbackPopupInput, FeedbackPopupType } from "./feedback-popup-types"

const DEFAULT_AUTO_DISMISS_MS = 2500

type FeedbackPopupState = {
  isOpen: boolean
  message: string
  type: FeedbackPopupType
  title?: string
  persist: boolean
  dismissLabel?: string
}

export type UseFeedbackPopupOptions = {
  autoDismissMs?: number
}

export function useFeedbackPopup(options?: UseFeedbackPopupOptions) {
  const autoDismissMs = options?.autoDismissMs ?? DEFAULT_AUTO_DISMISS_MS

  const [state, setState] = useState<FeedbackPopupState>({
    isOpen: false,
    message: "",
    type: "success",
    persist: false,
  })

  const closePopup = useCallback(() => {
    setState((prev) => ({ ...prev, isOpen: false }))
  }, [])

  const showPopup = useCallback((input: FeedbackPopupInput) => {
    if (
      process.env.NODE_ENV !== "production" &&
      input.title === "Getting Started Progress"
    ) {
      console.log("[getting-started] useFeedbackPopup showPopup", input.title)
    }
    setState({
      isOpen: true,
      message: input.message,
      type: input.type ?? "success",
      title: input.title,
      persist: input.persist === true,
      dismissLabel: input.dismissLabel,
    })
  }, [])

  useEffect(() => {
    if (!state.isOpen || state.persist) return
    const timer = setTimeout(closePopup, autoDismissMs)
    return () => clearTimeout(timer)
  }, [state.isOpen, state.persist, closePopup, autoDismissMs])

  const feedbackModalProps: FeedbackModalProps = {
    isOpen: state.isOpen,
    message: state.message,
    type: state.type,
    title: state.title,
    dismissLabel: state.dismissLabel,
    onClose: closePopup,
  }

  return {
    showPopup,
    closePopup,
    feedbackModalProps,
  }
}
