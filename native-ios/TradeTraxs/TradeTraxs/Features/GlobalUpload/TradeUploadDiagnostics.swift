import Foundation

#if DEBUG
enum TradeUploadDiagnostics {
    static func log(
        jobID: String,
        stage: String,
        tradeID: String? = nil,
        socialPostRequested: Bool? = nil,
        socialPostID: String? = nil,
        reelSelected: Bool? = nil,
        reelLinked: Bool? = nil,
        progress: Double? = nil
    ) {
        var line = "[TRADE_UPLOAD] jobID=\(jobID) stage=\(stage)"
        if let tradeID { line += " tradeID=\(tradeID)" }
        if let socialPostRequested { line += " socialPostRequested=\(socialPostRequested)" }
        if let socialPostID { line += " socialPostID=\(socialPostID)" }
        if let reelSelected { line += " reelSelected=\(reelSelected)" }
        if let reelLinked { line += " reelLinked=\(reelLinked)" }
        if let progress {
            let clamped = min(1, max(0, progress))
            line += " progress=\(String(format: "%.2f", clamped))"
        }
        print(line)
    }
}
#else
enum TradeUploadDiagnostics {
    static func log(
        jobID: String,
        stage: String,
        tradeID: String? = nil,
        socialPostRequested: Bool? = nil,
        socialPostID: String? = nil,
        reelSelected: Bool? = nil,
        reelLinked: Bool? = nil,
        progress: Double? = nil
    ) {}
}
#endif
