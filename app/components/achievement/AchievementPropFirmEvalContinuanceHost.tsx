"use client"

import { useCallback, useState } from "react"
import type { SupabaseClient } from "@supabase/supabase-js"
import CreateAccountModal from "@/app/components/CreateAccountModal"
import PropFirmEvalContinuanceModal from "@/app/components/propfirm/PropFirmEvalContinuanceModal"
import { resolveAccountModeForSave } from "@/lib/createAccountForm"
import { invalidateAccountsCache } from "@/lib/appDataCache"
import {
  buildCreateFundedAccountFormInitial,
  graduatePropFirmEvalToFunded,
  type PropFirmMilestoneAccount,
} from "@/lib/propfirmMilestones"
import type { CreateTradingAccountPayload } from "@/lib/tradingAccounts"

type AchievementPropFirmEvalContinuanceHostProps = {
  supabase: SupabaseClient
  userId: string | null
  onComplete?: () => void
}

export function useAchievementPropFirmEvalContinuance({
  supabase,
  userId,
  onComplete,
}: AchievementPropFirmEvalContinuanceHostProps) {
  const [evalContinuanceOpen, setEvalContinuanceOpen] = useState(false)
  const [graduateFundedEditorOpen, setGraduateFundedEditorOpen] = useState(false)
  const [evalContinuanceAccount, setEvalContinuanceAccount] =
    useState<PropFirmMilestoneAccount | null>(null)
  const [evalContinuanceBusy, setEvalContinuanceBusy] = useState(false)

  const closeEvalMilestoneFlow = useCallback(() => {
    if (evalContinuanceBusy) return
    setEvalContinuanceOpen(false)
    setGraduateFundedEditorOpen(false)
    setEvalContinuanceAccount(null)
    onComplete?.()
  }, [evalContinuanceBusy, onComplete])

  const openPassedEvalContinuance = useCallback(
    (account: PropFirmMilestoneAccount) => {
      setEvalContinuanceAccount(account)
      setEvalContinuanceOpen(true)
    },
    []
  )

  const handleOpenGraduateFundedSetup = useCallback(() => {
    setEvalContinuanceOpen(false)
    setGraduateFundedEditorOpen(true)
  }, [])

  const handleGraduateFundedSave = useCallback(
    async (account: CreateTradingAccountPayload) => {
      if (!userId || !evalContinuanceAccount) return

      setEvalContinuanceBusy(true)
      try {
        const { error } = await graduatePropFirmEvalToFunded(
          supabase,
          userId,
          evalContinuanceAccount,
          {
            name: account.name,
            size: account.size,
            id: account.id,
            category: "Prop Firm",
            mode: resolveAccountModeForSave("Prop Firm", "Funded"),
            rules: account.rules,
            purchaseCost: account.purchaseCost,
            purchaseDate: account.purchaseDate,
          }
        )
        if (error) {
          console.error(error)
          return
        }

        invalidateAccountsCache(userId)
        closeEvalMilestoneFlow()
      } finally {
        setEvalContinuanceBusy(false)
      }
    },
    [
      closeEvalMilestoneFlow,
      evalContinuanceAccount,
      supabase,
      userId,
    ]
  )

  const evalContinuanceModals = (
    <>
      <PropFirmEvalContinuanceModal
        open={evalContinuanceOpen}
        account={evalContinuanceAccount}
        busy={evalContinuanceBusy}
        onClose={closeEvalMilestoneFlow}
        onSetUpFundedAccount={handleOpenGraduateFundedSetup}
      />

      <CreateAccountModal
        open={graduateFundedEditorOpen}
        onClose={() => {
          if (!evalContinuanceBusy) {
            setGraduateFundedEditorOpen(false)
            setEvalContinuanceOpen(true)
          }
        }}
        initialAccount={
          evalContinuanceAccount
            ? buildCreateFundedAccountFormInitial(evalContinuanceAccount)
            : null
        }
        onSave={handleGraduateFundedSave}
        dialogTitle="Set Up Funded Account"
        dialogSubtitle="Evaluation history stays on your eval account. Configure your funded account and rules below."
        saveLabel="Create Funded Account"
        lockCategory="Prop Firm"
        lockMode="Funded"
      />
    </>
  )

  return {
    openPassedEvalContinuance,
    evalContinuanceModals,
    evalContinuanceBusy,
  }
}