import AppKit
import RSCore

enum KeyboardKeyCoder {
	static func dictionary(from key: KeyboardKey) -> [String: Any] {
		["i": key.integerValue, "shift": key.shiftKeyDown, "option": key.optionKeyDown, "command": key.commandKeyDown, "control": key.controlKeyDown]
	}
	static func key(from dictionary: [String: Any]) -> KeyboardKey? {
		guard let i = dictionary["i"] as? Int else { return nil }
		return KeyboardKey(integerValue: i,
						   shiftKeyDown: dictionary["shift"] as? Bool ?? false,
						   optionKeyDown: dictionary["option"] as? Bool ?? false,
						   commandKeyDown: dictionary["command"] as? Bool ?? false,
						   controlKeyDown: dictionary["control"] as? Bool ?? false)
	}
}
