import AppKit
import RSCore

extension KeyboardKey {

	var displayString: String {
		var result = ""
		if controlKeyDown { result += "⌃" }
		if optionKeyDown { result += "⌥" }
		if shiftKeyDown { result += "⇧" }
		if commandKeyDown { result += "⌘" }
		result += keyDisplayString
		return result
	}

	private var keyDisplayString: String {
		switch integerValue {
		case 32:
			return NSLocalizedString("Space", comment: "Space key")
		case NSUpArrowFunctionKey:
			return "↑"
		case NSDownArrowFunctionKey:
			return "↓"
		case NSLeftArrowFunctionKey:
			return "←"
		case NSRightArrowFunctionKey:
			return "→"
		case NSCarriageReturnCharacter, NSEnterCharacter:
			return "↩"
		case NSTabCharacter:
			return "⇥"
		case 127, NSDeleteFunctionKey:
			return "⌫"
		default:
			guard let scalar = Unicode.Scalar(integerValue) else { return "" }
			return String(Character(scalar)).uppercased()
		}
	}
}
