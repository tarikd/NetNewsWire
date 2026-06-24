import XCTest
import AppKit
import RSCore
@testable import NetNewsWire

final class KeyboardKeyDisplayTests: XCTestCase {
	private func k(_ i: Int, cmd: Bool = false, shift: Bool = false) -> KeyboardKey { KeyboardKey(integerValue: i, shiftKeyDown: shift, optionKeyDown: false, commandKeyDown: cmd, controlKeyDown: false) }
	func testPlainLetter() { XCTAssertEqual(k(110).displayString, "N") }
	func testCommandLetter() { XCTAssertEqual(k(110, cmd: true).displayString, "⌘N") }
	func testSpace() { XCTAssertEqual(k(32).displayString, "Space") }
	func testArrow() { XCTAssertEqual(k(NSRightArrowFunctionKey).displayString, "→") }
}
