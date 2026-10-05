import XCTest
@testable import TradeTraxs

final class DemoAdminEditorTests: XCTestCase {
    func testDemoModeIsHiddenFromNonAdmins() {
        XCTAssertFalse(DemoAdminEntry.isAvailable(isPlatformAdmin: false))
        XCTAssertTrue(DemoAdminEntry.isAvailable(isPlatformAdmin: true))
        XCTAssertEqual(DemoAdminEntry.rowTitle, "Demo Mode")
    }

    func testSavePublishesThroughTheExistingAdminRPC() async throws {
        let rpc = ScriptedDemoRPC(results: [
            .success(demoState(ok: true, version: 4)),
            .success(demoState(ok: true, version: 5)),
        ])
        let saved = try await DemoAdminService(rpc: rpc, media: nil).saveAndPublish(
            entity: "trade",
            record: ["id": "demo-trade-2-0", "realizedPnL": ["amount": 900, "currencyCode": "USD"]]
        )
        XCTAssertEqual(saved.publishedVersion, 5)
        XCTAssertEqual(rpc.commands, ["save", "publish"])
        XCTAssertEqual(rpc.functions, [DemoAdminService.rpcFunction, DemoAdminService.rpcFunction])
        let record = rpc.payloads.first?["record"] as? [String: Any]
        XCTAssertEqual(DemoJSON.int((record?["realizedPnL"] as? [String: Any])?["amount"]), 900)
    }

    func testInvalidPublishDiscardsTheDraft() async {
        let rpc = ScriptedDemoRPC(results: [
            .success(demoState(ok: true, version: 4)),
            .success(demoState(ok: false, version: 4, errors: ["Trade demo-trade-2-0 is incomplete."])),
            .success(demoState(ok: true, version: 4)),
        ])
        do {
            _ = try await DemoAdminService(rpc: rpc, media: nil).saveAndPublish(entity: "trade", record: ["id": "demo-trade-2-0"])
            XCTFail("Expected validation to stop publication")
        } catch let error as DemoAdminError {
            guard case .validation = error else {
                return XCTFail("Expected validation, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(rpc.commands, ["save", "publish", "discard"])
    }

    func testAdminRejectionDoesNotLookLikeAMissingSession() async {
        let rpc = ScriptedDemoRPC(results: [.failure(AppError.authentication(.sessionMissing))])
        do {
            _ = try await DemoAdminService(rpc: rpc, media: nil).load()
            XCTFail("Expected admin rejection")
        } catch let error as DemoAdminError {
            XCTAssertEqual(error, .accessRequired)
            XCTAssertEqual(error.message, "Admin access is required.")
            XCTAssertFalse(error.message.contains("sessionMissing"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testDemoMediaPathsCannotPointAtProductionStorage() {
        XCTAssertTrue(DemoMediaPath.isOwned("demo/trade/demo-trade-2-0/file.jpg"))
        XCTAssertFalse(DemoMediaPath.isOwned("avatars/user/file.jpg"))
        XCTAssertFalse(DemoMediaPath.isOwned("demo/../avatars/file.jpg"))
        XCTAssertNil(DemoMediaPath.from(url: "https://example.supabase.co/storage/v1/object/public/avatars/a.jpg"))
        let owned = DemoMediaPath.from(url: "https://example.supabase.co/storage/v1/object/public/demo-media/demo/profile/demo.explore.trader/a.jpg")
        XCTAssertEqual(owned, "demo/profile/demo.explore.trader/a.jpg")
    }

    func testTradeSelectorLabelDoesNotExposeTheRecordID() {
        let trade = DemoObject([
            "id": "2ac7-hidden",
            "symbol": ["ticker": "MNQ"],
            "realizedPnL": ["amount": 620],
            "entryAt": "2026-10-01T14:00:00Z",
        ])
        let label = DemoAdminLabels.trade(trade, account: "Apex 50K Funded · Funded")
        XCTAssertTrue(label.contains("MNQ"))
        XCTAssertTrue(label.contains("620"))
        XCTAssertTrue(label.contains("Apex 50K Funded"))
        XCTAssertFalse(label.contains("2ac7-hidden"))
    }

    func testValidationTextUsesReadableNames() {
        let draft: [String: Any] = [
            "profiles": [],
            "accounts": [["id": "acct-1", "name": "Apex 50K Funded", "mode": "funded"]],
            "trades": [[
                "id": "demo-trade-2-0",
                "accountID": "acct-1",
                "symbol": ["ticker": "MNQ"],
                "realizedPnL": ["amount": 620],
                "entryAt": "2026-10-01T00:00:00Z",
            ]],
        ]
        let text = DemoAdminLabels.humanize(
            "Trade demo-trade-2-0 references account acct-1, which does not exist.",
            draft: draft
        )
        XCTAssertFalse(text.contains("demo-trade-2-0"))
        XCTAssertFalse(text.contains("acct-1"))
        XCTAssertTrue(text.contains("MNQ"))
        XCTAssertTrue(text.contains("Apex 50K Funded"))
    }

    func testAvatarUploadResultIsStoredOnTheProfileRecord() {
        var form = DemoObject([
            "id": "demo.explore.trader",
            "avatar": ["id": "bundle:AppLogo", "kind": "image", "altText": "TradeTraxs logo"],
        ])
        let url = "https://cdn.example.com/storage/v1/object/public/demo-media/demo/profile/demo.explore.trader/avatar.jpg"
        DemoAdminMediaAssignment.apply(form: &form, path: "avatar", objectKey: "avatar", url: url, kind: "image", array: false)
        let avatar = form.value("avatar") as? [String: Any]
        XCTAssertEqual(avatar?["id"] as? String, url)
        XCTAssertEqual(avatar?["kind"] as? String, "image")

        DemoAdminMediaAssignment.apply(form: &form, path: "thumbnail", objectKey: "thumbnail", url: url, kind: "image", array: false)
        XCTAssertEqual((form.value("thumbnail") as? [String: Any])?["id"] as? String, url)

        DemoAdminMediaAssignment.apply(form: &form, path: "media", objectKey: "media", url: url, kind: "image", array: true)
        let media = (form.value("media") as? [Any])?.first as? [String: Any]
        XCTAssertEqual(media?["id"] as? String, url)

        DemoAdminMediaAssignment.apply(form: &form, path: "media", objectKey: "media", url: url, kind: "video", array: false)
        XCTAssertEqual((form.value("media") as? [String: Any])?["kind"] as? String, "video")
    }

    func testRestoreUsesTheExistingRestoreCommand() async throws {
        let rpc = ScriptedDemoRPC(results: [.success(demoState(ok: true, version: 6))])
        _ = try await DemoAdminService(rpc: rpc, media: nil).restore(version: 4)
        XCTAssertEqual(rpc.commands, ["restore"])
        XCTAssertEqual(rpc.functions, [DemoAdminService.rpcFunction])
        XCTAssertEqual(DemoJSON.int(rpc.payloads.first?["version"]), 4)
    }
}

private nonisolated final class ScriptedDemoRPC: DemoAdminRPCClient, @unchecked Sendable {
    var functions: [String] = []
    var commands: [String] = []
    var payloads: [[String: Any]] = []
    var results: [Result<Data, Error>]

    init(results: [Result<Data, Error>]) {
        self.results = results
    }

    func rpc(functionName: String, body: Data) async throws -> Data {
        functions.append(functionName)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        commands.append(json?["p_command"] as? String ?? "")
        payloads.append(json?["p_payload"] as? [String: Any] ?? [:])
        return try results.removeFirst().get()
    }
}

private func demoState(ok: Bool, version: Int, errors: [String] = []) -> Data {
    let object: [String: Any] = [
        "ok": ok,
        "errors": errors,
        "publishedVersion": version,
        "published": ["version": version, "isCurrent": true],
        "history": [["version": version, "isCurrent": true, "publishedAt": "2026-10-03T00:00:00Z"]],
        "draft": ["trades": []],
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}
