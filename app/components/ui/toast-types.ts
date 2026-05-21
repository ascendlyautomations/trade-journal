export type ToastType = "success" | "error" | "info" | "warning"

export type ToastItem = {
  id: string
  message: string
  type: ToastType
  duration: number
}

export type ToastInput = {
  message: string
  type?: ToastType
  duration?: number
}
