import Foundation
import os

#if DEBUG
nonisolated enum VoicePlaybackLog {
    private static let logger = AppLog.realtime

    static let tracedMessageID = "b16ada6d-1769-4086-aa68-b02fda3737a2"

    nonisolated static func prepare(_ fields: VoicePlaybackPrepareFields) {
        let trace = fields.messageID == tracedMessageID ? " traceTarget=new-web-wav" : ""
        logger.debug(
            """
            [VoicePlayback]\(trace) messageID=\(fields.messageID, privacy: .public) \
            audioURL=\(fields.audioURL, privacy: .public) fileExtension=\(fields.fileExtension, privacy: .public) \
            declaredContentType=\(fields.declaredContentType, privacy: .public) source=\(fields.source, privacy: .public) \
            downloadBytes=\(fields.downloadBytes.map(String.init) ?? "nil", privacy: .public) \
            httpStatus=\(fields.httpStatus.map(String.init) ?? "nil", privacy: .public) \
            responseContentType=\(fields.responseContentType ?? "nil", privacy: .public) \
            cachedLocalPath=\(fields.cachedLocalPath, privacy: .public) cachedFileExtension=\(fields.cachedFileExtension, privacy: .public) \
            remoteExtension=\(fields.remoteExtension, privacy: .public) resolvedContainer=\(fields.resolvedContainer, privacy: .public) \
            cacheExtension=\(fields.cacheExtension, privacy: .public) extensionMismatch=\(fields.extensionMismatch, privacy: .public)
            """
        )
    }

    nonisolated static func asset(_ fields: VoicePlaybackAssetFields) {
        let trace = fields.messageID == tracedMessageID ? " traceTarget=new-web-wav" : ""
        logger.debug(
            """
            [VoicePlayback]\(trace) messageID=\(fields.messageID, privacy: .public) \
            assetPlayable=\(fields.assetPlayable.map { String($0) } ?? "nil", privacy: .public) \
            assetDuration=\(fields.assetDurationSeconds.map { String(format: "%.3f", $0) } ?? "nil", privacy: .public) \
            audioTrackCount=\(fields.audioTrackCount, privacy: .public) \
            audioFormatDescriptions=\(fields.audioFormatDescriptions, privacy: .public) \
            decodedPcmPeak=\(fields.decodedPcmPeak.map { String(format: "%.6f", $0) } ?? "nil", privacy: .public)
            """
        )
    }

    nonisolated static func wavHeader(
        messageID: String,
        riffHeaderValid: Bool,
        waveHeaderValid: Bool,
        fileBytes: Int,
        fmtSampleRate: Int?,
        fmtChannels: Int?,
        fmtBitsPerSample: Int?,
        dataChunkBytes: Int?
    ) {
        let trace = messageID == tracedMessageID ? " traceTarget=new-web-wav" : ""
        logger.debug(
            """
            [VoicePlayback]\(trace) containerDetected=wav messageID=\(messageID, privacy: .public) \
            riffHeaderValid=\(riffHeaderValid, privacy: .public) waveHeaderValid=\(waveHeaderValid, privacy: .public) \
            fileBytes=\(fileBytes, privacy: .public) fmtSampleRate=\(fmtSampleRate.map(String.init) ?? "nil", privacy: .public) \
            fmtChannels=\(fmtChannels.map(String.init) ?? "nil", privacy: .public) \
            fmtBitsPerSample=\(fmtBitsPerSample.map(String.init) ?? "nil", privacy: .public) \
            dataChunkBytes=\(dataChunkBytes.map(String.init) ?? "nil", privacy: .public)
            """
        )
    }

    nonisolated static func player(
        messageID: String,
        playerItemStatus: String,
        playerError: String?
    ) {
        let trace = messageID == tracedMessageID ? " traceTarget=new-web-wav" : ""
        logger.debug(
            """
            [VoicePlayback]\(trace) messageID=\(messageID, privacy: .public) \
            playerItemStatus=\(playerItemStatus, privacy: .public) \
            playerError=\(playerError ?? "nil", privacy: .public)
            """
        )
    }
}

nonisolated struct VoicePlaybackPrepareFields: Sendable {
    var messageID: String
    var audioURL: String
    var fileExtension: String
    var declaredContentType: String
    var source: String
    var downloadBytes: Int?
    var httpStatus: Int?
    var responseContentType: String?
    var cachedLocalPath: String
    var cachedFileExtension: String
    var remoteExtension: String
    var resolvedContainer: String
    var cacheExtension: String
    var extensionMismatch: Bool
}

nonisolated struct VoicePlaybackAssetFields: Sendable {
    var messageID: String
    var assetPlayable: Bool?
    var assetDurationSeconds: Double?
    var audioTrackCount: Int
    var audioFormatDescriptions: String
    var decodedPcmPeak: Double?
}
#else
nonisolated enum VoicePlaybackLog {
    static let tracedMessageID = "b16ada6d-1769-4086-aa68-b02fda3737a2"
    nonisolated static func prepare(_ fields: VoicePlaybackPrepareFields) {}
    nonisolated static func asset(_ fields: VoicePlaybackAssetFields) {}
    nonisolated static func wavHeader(
        messageID: String,
        riffHeaderValid: Bool,
        waveHeaderValid: Bool,
        fileBytes: Int,
        fmtSampleRate: Int?,
        fmtChannels: Int?,
        fmtBitsPerSample: Int?,
        dataChunkBytes: Int?
    ) {}
    nonisolated static func player(messageID: String, playerItemStatus: String, playerError: String?) {}
}

nonisolated struct VoicePlaybackPrepareFields: Sendable {
    var messageID: String
    var audioURL: String
    var fileExtension: String
    var declaredContentType: String
    var source: String
    var downloadBytes: Int?
    var httpStatus: Int?
    var responseContentType: String?
    var cachedLocalPath: String
    var cachedFileExtension: String
    var remoteExtension: String
    var resolvedContainer: String
    var cacheExtension: String
    var extensionMismatch: Bool
}

nonisolated struct VoicePlaybackAssetFields: Sendable {
    var messageID: String
    var assetPlayable: Bool?
    var assetDurationSeconds: Double?
    var audioTrackCount: Int
    var audioFormatDescriptions: String
    var decodedPcmPeak: Double?
}
#endif
