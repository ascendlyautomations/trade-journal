"use client"

import { useCallback, useEffect, useState } from "react"
import type { FeedbackModalProps } from "./FeedbackModal"
import type { FeedbackPopupInput, FeedbackPopupType } from "./feedback-popup-types"

const DEFAULT_AUTO_DISMISS_MS = 2500

type FeedbackPopupState = {
  isOpen: boolean
  message: string
  type: FeedbackPopupType
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
  })

  const closePopup = useCallback(() => {
    setState((prev) => ({ ...prev, isOpen: false }))
  }, [])

  const showPopup = useCallback((input: FeedbackPopupInput) => {
    setState({
      isOpen: true,
      message: input.message,
      type: input.type ?? "success",
    })
  }, [])

  useEffect(() => {
    if (!state.isOpen) return
    const timer = setTimeout(closePopup, autoDismissMs)
    return () => clearTimeout(timer)
  }, [state.isOpen, closePopup, autoDismissMs])

  const feedbackModalProps: FeedbackModalProps = {
    isOpen: state.isOpen,
    message: state.message,
    type: state.type,
    onClose: closePopup,
  }

  return {
    showPopup,
    closePopup,
    feedbackModalProps,
  }
}
