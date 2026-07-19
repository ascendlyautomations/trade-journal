"use client"

import { useCallback, useState } from "react"
import type { DashboardTradeRow } from "@/app/components/dashboard/dashboardTypes"

export function useDashboardModals() {
  const [performanceShareOpen, setPerformanceShareOpen] = useState(false)
  const [quickTradeOpen, setQuickTradeOpen] = useState(false)
  const [upgradeOpen, setUpgradeOpen] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [editingTrade, setEditingTrade] = useState<DashboardTradeRow | null>(null)
  const [selectedImage, setSelectedImage] = useState<string | null>(null)
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)

  const openPerformanceShare = useCallback(
    () => setPerformanceShareOpen(true),
    []
  )
  const closePerformanceShare = useCallback(
    () => setPerformanceShareOpen(false),
    []
  )
  const openQuickTrade = useCallback(() => setQuickTradeOpen(true), [])
  const closeQuickTrade = useCallback(() => setQuickTradeOpen(false), [])
  const openUpgrade = useCallback(() => setUpgradeOpen(true), [])
  const closeUpgrade = useCallback(() => setUpgradeOpen(false), [])
  const openImport = useCallback(() => setImportOpen(true), [])
  const closeImport = useCallback(() => setImportOpen(false), [])
  const closeTrade = useCallback(() => setEditingTrade(null), [])
  const closeImage = useCallback(() => setSelectedImage(null), [])
  const closeSend = useCallback(() => setSendTradeId(null), [])

  return {
    performanceShareOpen,
    openPerformanceShare,
    closePerformanceShare,
    quickTradeOpen,
    openQuickTrade,
    closeQuickTrade,
    upgradeOpen,
    openUpgrade,
    closeUpgrade,
    importOpen,
    openImport,
    closeImport,
    editingTrade,
    setEditingTrade,
    selectedImage,
    setSelectedImage,
    closeImage,
    sendTradeId,
    setSendTradeId,
    closeSend,
    closeTrade,
  }
}
