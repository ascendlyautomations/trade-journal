import type { Metadata } from "next"
import {
  buildTradeMetadata,
  fetchTradeForSeo,
} from "@/lib/publicSeo"
import TradeDetailPageClient from "./TradeDetailPageClient"

type TradePageProps = {
  params: Promise<{ id: string }>
}

export async function generateMetadata({
  params,
}: TradePageProps): Promise<Metadata> {
  const { id } = await params
  const result = await fetchTradeForSeo(id)
  if (!result) {
    return buildTradeMetadata(null, null)
  }
  return buildTradeMetadata(result.trade, result.owner)
}

export default async function TradeDetailPage({ params }: TradePageProps) {
  const { id } = await params
  const tradeId =
    typeof id === "string" ? id : Array.isArray(id) ? id[0] : ""

  return <TradeDetailPageClient tradeId={tradeId} />
}
