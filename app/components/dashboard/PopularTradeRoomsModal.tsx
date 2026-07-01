"use client"

import { useRouter } from "next/navigation"
import Modal from "@/app/components/ui/Modal"
import PopularTradeRoomsPanel from "@/app/components/dashboard/PopularTradeRoomsPanel"
import type { PopularTradeRoom } from "@/lib/popularTradeRooms"

export type PopularTradeRoomsModalProps = {
  open: boolean
  onClose: () => void
  onJoined?: () => void
}

export default function PopularTradeRoomsModal({
  open,
  onClose,
  onJoined,
}: PopularTradeRoomsModalProps) {
  const router = useRouter()

  function handleJoined(room: PopularTradeRoom) {
    onJoined?.()
    onClose()
    const target = room.slug ?? room.id
    router.push(`/trade-rooms?room=${encodeURIComponent(String(target))}`)
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Popular Trade Rooms"
      size="lg"
      backdropClassName="bg-black/80 backdrop-blur-lg"
    >
      <PopularTradeRoomsPanel active={open} onJoined={handleJoined} />
    </Modal>
  )
}
