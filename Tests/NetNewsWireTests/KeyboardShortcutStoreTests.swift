import XCTest
import RSCore
@testable import NetNewsWire

@MainActor
final class KeyboardShortcutStoreTests: XCTestCase {
	private func key(_ i: Int) -> KeyboardKey { KeyboardKey(integerValue: i, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false) }
	private func command(_ action: String, _ i: Int, current: KeyboardKey?) -> KeyboardShortcutStore.Command {
		KeyboardShortcutStore.Command(title: action, action: action, defaultKey: key(i), currentKey: current)
	}

	func testOverrideReplacesDefault() {
		let defaults = [command("next:", 110, current: key(110))]
		XCTAssertEqual(KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: ["next:": .some(key(114))])[0].currentKey, key(114))
	}
	func testUnbindOverride() {
		let defaults = [command("next:", 110, current: key(110))]
		XCTAssertNil(KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: ["next:": .some(nil)])[0].currentKey)
	}
	func testUntouchedKeepsDefault() {
		let defaults = [command("next:", 110, current: key(110))]
		XCTAssertEqual(KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: [:])[0].currentKey, key(110))
	}
	func testConflictDetected() {
		let commands = [command("a:", 110, current: key(110)), command("b:", 114, current: nil)]
		XCTAssertEqual(KeyboardShortcutStore.conflictingAction(for: key(110), assigningTo: "b:", in: commands), "a:")
		XCTAssertNil(KeyboardShortcutStore.conflictingAction(for: key(110), assigningTo: "a:", in: commands))
	}
}
