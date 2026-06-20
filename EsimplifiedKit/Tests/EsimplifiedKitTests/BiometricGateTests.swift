import XCTest
@testable import EsimplifiedKit

final class BiometricGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_neverBackgrounded_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: nil, now: t0, grace: 180))
    }
    func test_withinGrace_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(120), grace: 180))
    }
    func test_pastGrace_relocks() {
        XCTAssertTrue(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(181), grace: 180))
    }
    func test_exactlyAtGrace_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(180), grace: 180))
    }
}
