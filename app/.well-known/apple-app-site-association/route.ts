import { appleAppSiteAssociationResponse } from "@/lib/appleAppSiteAssociation"

export const dynamic = "force-static"

export function GET() {
  return appleAppSiteAssociationResponse()
}
