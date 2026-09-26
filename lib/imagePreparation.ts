import {
  renderContentImageV2,
  type RenderContentImageV2Options,
} from "./renderContentImageV2"
import { renderBoundedJpeg, renderFixedCoverImage } from "./renderSemanticImage"
import type { ContentCoverTransform } from "./contentImageV2"

/**
 * Shared image preparation. Each preset is a semantic contract.
 * Callers upload the returned JPEG. They must not compress it again.
 */
export type ImagePreparationPresetId =
  | "contentV2"
  | "avatar"
  | "story"
  | "chat"
  | "room"
  | "attachment"

export type ImagePreparationStatus = "ready" | "deferred"

export const IMAGE_PREPARATION_STATUS: Record<
  ImagePreparationPresetId,
  ImagePreparationStatus
> = {
  contentV2: "ready",
  avatar: "ready",
  story: "ready",
  chat: "ready",
  room: "ready",
  attachment: "ready",
}

export function imagePreparationStatus(
  preset: ImagePreparationPresetId
): ImagePreparationStatus {
  return IMAGE_PREPARATION_STATUS[preset]
}

export type ImagePreparationOptions = {
  aspect?: RenderContentImageV2Options["aspect"]
  transform?: ContentCoverTransform
}

export async function prepareImageForUpload(
  preset: ImagePreparationPresetId,
  file: File,
  options?: ImagePreparationOptions
): Promise<File> {
  if (preset === "contentV2") {
    if (!options?.aspect || !options.transform) {
      throw new Error("contentV2 preparation requires an aspect and transform.")
    }
    return renderContentImageV2(file, {
      aspect: options.aspect,
      transform: options.transform,
    })
  }

  if (preset === "avatar" || preset === "room") {
    return renderFixedCoverImage(file, {
      kind: "avatar",
      transform: options?.transform,
    })
  }

  if (preset === "story") {
    return renderFixedCoverImage(file, {
      kind: "story",
      transform: options?.transform,
    })
  }

  if (preset === "chat" || preset === "attachment") {
    return renderBoundedJpeg(file, preset)
  }

  throw new Error(`${preset} image preparation is not available.`)
}
