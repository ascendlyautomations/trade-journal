"use client"

import { useCallback, useState } from "react"
import type { SupabaseClient } from "@supabase/supabase-js"
import CreateAccountModal from "@/app/components/CreateAccountModal"
import PropFirmEvalContinuanceModal from "@/app/components/propfirm/PropFirmEvalContinuanceModal"
import PropFirmFundedRulesChoiceModal from "@/app/components/propfirm/PropFirmFundedRulesChoiceModal"
import { resolveAccountModeForSave } from "@/lib/createAccountForm"
import { invalidateAccountsCache } from "@/lib/appDataCache"
import {
  buildConvertEvalToFundedFormInitial,
  buildCreateFundedAccountFormInitial,
  convertEvalAccountToFundedWithRules,
  type PropFirmMilestoneAccount,
} from "@/lib/propfirmMilestones"
import {
  insertTradingAccount,
  type CreateTradingAccountPayload,
} from "@/lib/tradingAccounts"

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
  const [evalRulesChoiceOpen, setEvalRulesChoiceOpen] = useState(false)
  const [convertRulesEditorOpen, setConvertRulesEditorOpen] = useState(false)
  const [createFundedAccountOpen, setCreateFundedAccountOpen] = useState(false)
  const [evalContinuanceAccount, setEvalContinuanceAccount] =
    useState<PropFirmMilestoneAccount | null>(null)
  const [convertRulesSameAsEval, setConvertRulesSameAsEval] = useState(false)
  const [evalContinuanceBusy, setEvalContinuanceBusy] = useState(false)

  const closeEvalMilestoneFlow = useCallback(() => {
    if (evalContinuanceBusy) return
    setEvalContinuanceOpen(false)
    setEvalRulesChoiceOpen(false)
    setConvertRulesEditorOpen(false)
    setCreateFundedAccountOpen(false)
    setEvalContinuanceAccount(null)
    setConvertRulesSameAsEval(false)
    onComplete?.()
  }, [evalContinuanceBusy, onComplete])

  const openPassedEvalContinuance = useCallback(
    (account: PropFirmMilestoneAccount) => {
      setEvalContinuanceAccount(account)
      setEvalContinuanceOpen(true)
    },
    []
  )

  const handleConvertEvalToFunded = useCallback(() => {
    setEvalContinuanceOpen(false)
    setEvalRulesChoiceOpen(true)
  }, [])

  const openConvertRulesEditor = useCallback((sameAsEval: boolean) => {
    setConvertRulesSameAsEval(sameAsEval)
    setEvalRulesChoiceOpen(false)
    setConvertRulesEditorOpen(true)
  }, [])

  const handleOpenCreateFundedAccount = useCallback(() => {
    setEvalContinuanceOpen(false)
    setCreateFundedAccountOpen(true)
  }, [])

  const handleConvertRulesSave = useCallback(
    async (account: CreateTradingAccountPayload) => {
      if (!userId || !evalContinuanceAccount) return

      setEvalContinuanceBusy(true)
      try {
        const { error } = await convertEvalAccountToFundedWithRules(
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

  const handleCreateFundedAccountSave = useCallback(
    async (account: CreateTradingAccountPayload) => {
      if (!userId || !evalContinuanceAccount) return

      setEvalContinuanceBusy(true)
      try {
        const { error } = await insertTradingAccount(supabase, userId, {
          name: account.name,
          size: account.size,
          id: account.id,
          category: "Prop Firm",
          mode: resolveAccountModeForSave("Prop Firm", "Funded"),
          rules: account.rules,
        })
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
        onConvertToFunded={handleConvertEvalToFunded}
        onCreateNewFundedAccount={handleOpenCreateFundedAccount}
      />

      <PropFirmFundedRulesChoiceModal
        open={evalRulesChoiceOpen}
        busy={evalContinuanceBusy}
        onClose={closeEvalMilestoneFlow}
        onKeepSameRules={() => openConvertRulesEditor(true)}
        onReviewRules={() => openConvertRulesEditor(false)}
      />

      <CreateAccountModal
        open={convertRulesEditorOpen}
        onClose={() => {
          if (!evalContinuanceBusy) {
            setConvertRulesEditorOpen(false)
            setEvalRulesChoiceOpen(true)
          }
        }}
        initialAccount={
          evalContinuanceAccount
            ? buildConvertEvalToFundedFormInitial(evalContinuanceAccount)
            : null
        }
        onSave={handleConvertRulesSave}
        dialogTitle="Funded Account Rules"
        dialogSubtitle={
          convertRulesSameAsEval
            ? "Your evaluation rules are pre-filled below. Press Continue if nothing changed."
            : "Review and update your funded account rules before continuing."
        }
        saveLabel="Continue"
        lockCategory="Prop Firm"
        lockMode="Funded"
      />

      <CreateAccountModal
        open={createFundedAccountOpen}
        onClose={() => {
          if (!evalContinuanceBusy) {
            setCreateFundedAccountOpen(false)
            setEvalContinuanceOpen(true)
          }
        }}
        initialAccount={
          evalContinuanceAccount
            ? buildCreateFundedAccountFormInitial(evalContinuanceAccount)
            : null
        }
        onSave={handleCreateFundedAccountSave}
        dialogTitle="Create Funded Account"
        dialogSubtitle="Your evaluation account stays unchanged. Trades are not moved automatically."
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
