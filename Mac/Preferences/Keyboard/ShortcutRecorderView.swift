//
//  ShortcutRecorderView.swift
//  NetNewsWire
//
//  A focusable control that records a keyboard shortcut. Click it to begin
//  recording, then press a key combination. Esc cancels.
//

import AppKit
import RSCore

@MainActor final class ShortcutRecorderView: NSView {

	var onRecord: ((KeyboardKey) -> Void)?

	var key: KeyboardKey? {
		didSet { needsDisplay = true }
	}

	private var isRecording = false {
		didSet { needsDisplay = true }
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override var intrinsicContentSize: NSSize {
		return NSSize(width: 120.0, height: 24.0)
	}

	override var acceptsFirstResponder: Bool {
		return true
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		isRecording = true
	}

	override func keyDown(with event: NSEvent) {
		guard isRecording else {
			super.keyDown(with: event)
			return
		}

		// Esc cancels recording.
		if event.keyCode == 53 {
			isRecording = false
			window?.makeFirstResponder(nil)
			return
		}

		let recordedKey = KeyboardKey(with: event)
		isRecording = false
		key = recordedKey
		onRecord?(recordedKey)
		window?.makeFirstResponder(nil)
	}

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		isRecording = false
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func draw(_ dirtyRect: NSRect) {
		let inset = bounds.insetBy(dx: 1.0, dy: 1.0)
		let path = NSBezierPath(roundedRect: inset, xRadius: 5.0, yRadius: 5.0)

		NSColor.controlBackgroundColor.setFill()
		path.fill()

		let isFocused = (window?.firstResponder === self)
		if isRecording || isFocused {
			NSColor.controlAccentColor.setStroke()
			path.lineWidth = 2.0
		} else {
			NSColor.separatorColor.setStroke()
			path.lineWidth = 1.0
		}
		path.stroke()

		let text: String
		let textColor: NSColor
		if isRecording {
			text = NSLocalizedString("Type shortcut…", comment: "Shortcut recorder")
			textColor = .secondaryLabelColor
		} else if let key {
			text = key.displayString
			textColor = .labelColor
		} else {
			text = NSLocalizedString("Click to add", comment: "Shortcut recorder")
			textColor = .secondaryLabelColor
		}

		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		paragraph.lineBreakMode = .byTruncatingTail
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
			.foregroundColor: textColor,
			.paragraphStyle: paragraph
		]
		let attributed = NSAttributedString(string: text, attributes: attributes)
		let textSize = attributed.size()
		let textRect = NSRect(x: bounds.minX,
							   y: bounds.midY - (textSize.height / 2.0),
							   width: bounds.width,
							   height: textSize.height)
		attributed.draw(in: textRect)
	}
}
