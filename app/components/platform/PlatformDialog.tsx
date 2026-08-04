"use client"

import ConfirmModal, {
  type ConfirmModalProps,
} from "@/app/components/ui/ConfirmModal"

export type PlatformDialogProps = ConfirmModalProps

/**
 * Confirmation presentation adapter.
 * ConfirmModal already branches to native dialog chrome on Capacitor iOS.
 */
export default function PlatformDialog(props: PlatformDialogProps) {
  return <ConfirmModal {...props} />
}
