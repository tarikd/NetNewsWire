import XCTest
@testable import NetNewsWire

final class SwipeDecisionTests: XCTestCase {

	func testRightToLeftWhileReadingOpensWeb() {
		XCTAssertEqual(SwipeDecider.action(deltaX: -1.0, isBrowsing: false), .openWeb)
	}

	func testLeftToRightWhileBrowsingReturns() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 1.0, isBrowsing: true), .returnToArticle)
	}

	func testRightToLeftWhileBrowsingIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: -1.0, isBrowsing: true), .ignore)
	}

	func testLeftToRightWhileReadingIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 1.0, isBrowsing: false), .ignore)
	}

	func testZeroDeltaIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 0.0, isBrowsing: false), .ignore)
		XCTAssertEqual(SwipeDecider.action(deltaX: 0.0, isBrowsing: true), .ignore)
	}
}
