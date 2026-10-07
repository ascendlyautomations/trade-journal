import XCTest
@testable import TradeTraxs

final class ProfileBioPolicyTests: XCTestCase {
    func testBioKeepsAtMostThreeLines() {
        XCTAssertEqual(ProfileBioPolicy.constrained("one\ntwo"), "one\ntwo")
        XCTAssertEqual(ProfileBioPolicy.constrained("one\ntwo\nthree"), "one\ntwo\nthree")
        XCTAssertEqual(ProfileBioPolicy.constrained("one\ntwo\nthree\nfour"), "one\ntwo\nthree")
        XCTAssertEqual(ProfileBioPolicy.constrained("one\r\ntwo\r\nthree\r\nfour"), "one\ntwo\nthree")
        XCTAssertEqual(ProfileBioPolicy.constrained("one\ntwo\nthree\n"), "one\ntwo\nthree")
    }

    func testPersistedBioDropsExtraLinesAndBlankInput() {
        XCTAssertEqual(ProfileBioPolicy.persisted("one\ntwo\nthree\nfour"), "one\ntwo\nthree")
        XCTAssertNil(ProfileBioPolicy.persisted("  \n  \n  "))
        XCTAssertNil(ProfileBioPolicy.persisted(nil))
    }

    func testEditDecisionRejectsReturnWhenAlreadyAtThreeLines() {
        let current = "one\ntwo\nthree"
        let range = NSRange(location: (current as NSString).length, length: 0)
        XCTAssertEqual(
            ProfileBioPolicy.editDecision(current: current, range: range, replacement: "\n"),
            .reject
        )
    }

    func testEditDecisionAcceptsReturnWhenUnderThreeLines() {
        let current = "one\ntwo"
        let range = NSRange(location: (current as NSString).length, length: 0)
        XCTAssertEqual(
            ProfileBioPolicy.editDecision(current: current, range: range, replacement: "\n"),
            .accept
        )
    }

    func testEditDecisionAppliesConstrainedPaste() {
        let current = "one"
        let range = NSRange(location: 3, length: 0)
        let pasted = "\ntwo\nthree\nfour"
        if case .apply(let applied) = ProfileBioPolicy.editDecision(
            current: current,
            range: range,
            replacement: pasted
        ) {
            XCTAssertEqual(applied, "one\ntwo\nthree")
        } else {
            XCTFail("Expected apply for over-limit paste")
        }
    }
}
