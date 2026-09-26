import AVFoundation
import Foundation

enum VoicePlaybackDiagnostics {
    struct ResolvedAudio: Sendable {
        var localURL: URL
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

    static func declaredContentType(for remoteURL: URL, responseType: String?) -> String {
        if let responseType, !responseType.isEmpty {
            return responseType
        }
        switch remoteURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        default:
            return "unknown"
        }
    }

    static func inspectWavFile(at url: URL, messageID: String) {
        guard let data = try? Data(contentsOf: url), data.count >= 44 else {
            VoicePlaybackLog.wavHeader(
                messageID: messageID,
                riffHeaderValid: false,
                waveHeaderValid: false,
                fileBytes: (try? Data(contentsOf: url))?.count ?? 0,
                fmtSampleRate: nil,
                fmtChannels: nil,
                fmtBitsPerSample: nil,
                dataChunkBytes: nil
            )
            return
        }

        let riff = String(data: data[0 ..< 4], encoding: .ascii) == "RIFF"
        let wave = data.count >= 12 && String(data: data[8 ..< 12], encoding: .ascii) == "WAVE"
        var sampleRate: Int?
        var channels: Int?
        var bitsPerSample: Int?
        var dataChunkBytes: Int?
        if data.count >= 44 {
            sampleRate = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }.littleEndian)
            channels = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 22, as: UInt16.self) }.littleEndian)
            bitsPerSample = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt16.self) }.littleEndian)
            dataChunkBytes = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }.littleEndian)
        }

        VoicePlaybackLog.wavHeader(
            messageID: messageID,
            riffHeaderValid: riff,
            waveHeaderValid: wave,
            fileBytes: data.count,
            fmtSampleRate: sampleRate,
            fmtChannels: channels,
            fmtBitsPerSample: bitsPerSample,
            dataChunkBytes: dataChunkBytes
        )
    }

    static func pcmPeakFromWavFile(at url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        guard String(data: data[0 ..< 4], encoding: .ascii) == "RIFF",
              String(data: data[8 ..< 12], encoding: .ascii) == "WAVE"
        else { return nil }
        let audioFormat = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt16.self) }.littleEndian
        guard audioFormat == 1 else { return nil }
        let bits = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt16.self) }.littleEndian)
        guard bits == 16 else { return nil }
        let dataSize = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 40, as: UInt32.self) }.littleEndian)
        let pcmStart = 44
        guard pcmStart + dataSize <= data.count else { return nil }
        var peak: Double = 0
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: pcmStart)
            let sampleCount = dataSize / 2
            for index in 0 ..< sampleCount {
                let sample = base.advanced(by: index * 2)
                    .assumingMemoryBound(to: Int16.self)
                    .pointee
                let normalized = abs(Double(sample) / 32768.0)
                if normalized > peak { peak = normalized }
            }
        }
        return peak
    }

    static func inspectAsset(at localURL: URL, messageID: String) async -> VoicePlaybackAssetFields {
        let asset = AVURLAsset(url: localURL)
        var playable: Bool?
        var durationSeconds: Double?
        var trackCount = 0
        var formatSummary = "none"

        if #available(iOS 16.0, *) {
            playable = try? await asset.load(.isPlayable)
            if let duration = try? await asset.load(.duration) {
                let seconds = duration.seconds
                durationSeconds = seconds.isFinite ? seconds : nil
            }
            if let tracks = try? await asset.loadTracks(withMediaType: .audio) {
                trackCount = tracks.count
                formatSummary = await formatDescriptions(for: tracks)
            }
        } else {
            playable = asset.isPlayable
            let seconds = asset.duration.seconds
            durationSeconds = seconds.isFinite ? seconds : nil
            let tracks = asset.tracks(withMediaType: .audio)
            trackCount = tracks.count
            var parts: [String] = []
            for track in tracks {
                for description in track.formatDescriptions {
                    let boxed = description as! CMFormatDescription
                    parts.append(String(format: "%u", CMFormatDescriptionGetMediaSubType(boxed)))
                }
            }
            formatSummary = parts.isEmpty ? "none" : parts.joined(separator: ",")
        }

        var pcmPeak: Double?
        let prefix = try? Data(contentsOf: localURL, options: [.mappedIfSafe]).prefix(4)
        let looksLikeWav = prefix == Data("RIFF".utf8)
        if localURL.pathExtension.lowercased() == "wav" || looksLikeWav {
            inspectWavFile(at: localURL, messageID: messageID)
            pcmPeak = pcmPeakFromWavFile(at: localURL)
        }

        return VoicePlaybackAssetFields(
            messageID: messageID,
            assetPlayable: playable,
            assetDurationSeconds: durationSeconds,
            audioTrackCount: trackCount,
            audioFormatDescriptions: formatSummary,
            decodedPcmPeak: pcmPeak
        )
    }

    @available(iOS 16.0, *)
    private static func formatDescriptions(for tracks: [AVAssetTrack]) async -> String {
        var parts: [String] = []
        for track in tracks {
            if let descriptions = try? await track.load(.formatDescriptions) {
                for description in descriptions {
                    let sub = CMFormatDescriptionGetMediaSubType(description)
                    parts.append(String(format: "%u", sub))
                }
            }
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    static func logPlayerItem(messageID: String, item: AVPlayerItem) {
        let status: String
        switch item.status {
        case .unknown:
            status = "unknown"
        case .readyToPlay:
            status = "readyToPlay"
        case .failed:
            status = "failed"
        @unknown default:
            status = "unknownDefault"
        }
        let errorDescription = item.error.map { String(describing: $0) }
        VoicePlaybackLog.player(
            messageID: messageID,
            playerItemStatus: status,
            playerError: errorDescription
        )
    }
}
