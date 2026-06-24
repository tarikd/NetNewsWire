import XCTest
import AppKit
import RSCore
@testable import NetNewsWire

final class KeyboardKeyCoderTests: XCTestCase {
	func testRoundTrip() {
		let key = KeyboardKey(integerValue: 110, shiftKeyDown: true, optionKeyDown: false, commandKeyDown: true, controlKeyDown: false)
		XCTAssertEqual(KeyboardKeyCoder.key(from: KeyboardKeyCoder.dictionary(from: key)), key)
	}
	func testSpecialKeyValuePreserved() {
		let up = KeyboardKey(integerValue: NSUpArrowFunctionKey, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		XCTAssertEqual(KeyboardKeyCoder.key(from: KeyboardKeyCoder.dictionary(from: up)), up)
	}
	func testInvalidDictionaryReturnsNil() {
		XCTAssertNil(KeyboardKeyCoder.key(from: [:]))
	}
}
