import Foundation

/// BFF client for the existing `/api/push/register` + `/api/push/unregister` pipeline.
///
/// No duplicate token storage on the server — reuses `device_push_tokens`.
protocol DevicePushTokenClienting: Sendable {
    func register(
        deviceToken: String,
        previousDeviceToken: String?,
        installationID: String?,
        appVersion: String?
    ) async throws

    func unregister(deviceToken: String?, allDevices: Bool) async throws
}

struct DevicePushTokenClient: DevicePushTokenClienting {
    private let transport: SupabaseTransport

    init(transport: SupabaseTransport) {
        self.transport = transport
    }

    func register(
        deviceToken: String,
        previousDeviceToken: String?,
        installationID: String?,
        appVersion: String?
    ) async throws {
        struct Body: Encodable {
            var deviceToken: String
            var previousDeviceToken: String?
            var installationId: String?
            var platform: String
            var appVersion: String?
        }

        let body = Body(
            deviceToken: deviceToken,
            previousDeviceToken: previousDeviceToken,
            installationId: installationID,
            platform: "ios",
            appVersion: appVersion
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/push/register",
            method: .post,
            body: data,
            requiresAuthentication: true
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Push registration failed (\(response.statusCode))")
        }
    }

    func unregister(deviceToken: String?, allDevices: Bool) async throws {
        struct Body: Encodable {
            var deviceToken: String?
            var allDevices: Bool?
        }

        let body = Body(
            deviceToken: allDevices ? nil : deviceToken,
            allDevices: allDevices ? true : nil
        )
        let data = try transport.encodeJSON(body)
        let response = try await transport.send(
            host: .bff,
            path: "/api/push/unregister",
            method: .post,
            body: data,
            // Allow token-only unregister after session teardown races.
            requiresAuthentication: false
        )
        guard (200 ... 299).contains(response.statusCode) else {
            throw AppError.unknown(message: "Push unregister failed (\(response.statusCode))")
        }
    }
}
