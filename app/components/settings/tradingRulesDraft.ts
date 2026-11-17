export type TradingRulesDraftApi = {
  hasUnsavedChanges: boolean
  saveAll: () => Promise<boolean>
  discardChanges: () => void
}
