import Foundation
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum SubmissionDeviceMetadata {
    static let bugReportPageURL = "ios://settings/support/bug-report"

    /// Synchronous environment string (hardware model via `utsname`; no UIKit).
    static func compactEnvironmentString(appDisplayName: String = "TradeTraxs") -> String {
        composedString(appDisplayName: appDisplayName, model: hardwareMachineIdentifier())
    }

    /// Bug-report insert path: preserves UIKit model fallback when `utsname` is empty.
    static func compactEnvironmentStringForSubmission(appDisplayName: String = "TradeTraxs") async -> String {
        let hardware = hardwareMachineIdentifier()
        #if canImport(UIKit)
        let model: String
        if hardware.isEmpty {
            model = await MainActor.run { UIDevice.current.model }
        } else {
            model = hardware
        }
        #else
        let model = hardware.isEmpty ? "iOS" : hardware
        #endif
        return composedString(appDisplayName: appDisplayName, model: model)
    }

    private static func composedString(appDisplayName: String, model: String) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let resolvedModel = model.isEmpty ? "iOS" : model
        return "\(appDisplayName) \(version) (\(build)) · \(os) · \(resolvedModel)"
    }

    private static func hardwareMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(String(UnicodeScalar(UInt8(value))))
        }
    }
}
