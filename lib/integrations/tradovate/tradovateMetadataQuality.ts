export type TradovateMetadataQuality =
  | "RESOLVED_PRODUCT"
  | "RESOLVED_CONTRACT"
  | "PERSISTED_VALID_HINT"
  | "LOCAL_FALLBACK"
  | "UNRESOLVED"

export function metadataQualityRank(quality: TradovateMetadataQuality): number {
  switch (quality) {
    case "RESOLVED_PRODUCT":
      return 4
    case "RESOLVED_CONTRACT":
      return 3
    case "PERSISTED_VALID_HINT":
      return 2
    case "LOCAL_FALLBACK":
      return 1
    case "UNRESOLVED":
    default:
      return 0
  }
}
