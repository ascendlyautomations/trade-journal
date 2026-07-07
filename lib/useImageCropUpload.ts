"use client"

import { useCallback, useRef, useState, type ChangeEvent, type RefObject } from "react"
import type { ImageCropPresetId } from "./imageCropPresets"
import { validateImageUpload } from "./uploadValidation"

type UseImageCropUploadOptions = {
  preset: ImageCropPresetId
  onCropped: (file: File) => void
  onValidationError?: (message: string) => void
}

export type UseImageCropUploadResult = {
  fileInputRef: RefObject<HTMLInputElement | null>
  cropSourceFile: File | null
  pickImage: () => void
  handleFileSelected: (file: File | undefined) => void
  handleInputChange: (event: ChangeEvent<HTMLInputElement>) => void
  handleCropCancel: () => void
  handleCropSave: (file: File) => void
  resetFileInput: () => void
}

export function useImageCropUpload({
  preset: _preset,
  onCropped,
  onValidationError,
}: UseImageCropUploadOptions): UseImageCropUploadResult {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [cropSourceFile, setCropSourceFile] = useState<File | null>(null)

  const resetFileInput = useCallback(() => {
    if (fileInputRef.current) fileInputRef.current.value = ""
  }, [])

  const handleFileSelected = useCallback(
    (file: File | undefined) => {
      if (!file) return
      const validationError = validateImageUpload(file)
      if (validationError) {
        onValidationError?.(validationError)
        resetFileInput()
        return
      }
      setCropSourceFile(file)
    },
    [onValidationError, resetFileInput]
  )

  const pickImage = useCallback(() => {
    fileInputRef.current?.click()
  }, [])

  const handleInputChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      handleFileSelected(event.target.files?.[0])
    },
    [handleFileSelected]
  )

  const handleCropCancel = useCallback(() => {
    setCropSourceFile(null)
    resetFileInput()
  }, [resetFileInput])

  const handleCropSave = useCallback(
    (file: File) => {
      onCropped(file)
      setCropSourceFile(null)
      resetFileInput()
    },
    [onCropped, resetFileInput]
  )

  return {
    fileInputRef,
    cropSourceFile,
    pickImage,
    handleFileSelected,
    handleInputChange,
    handleCropCancel,
    handleCropSave,
    resetFileInput,
  }
}
