//
//  MainWindowKeyboardHandler.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 12/19/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import AppKit
import RSCore

@MainActor final class MainWindowKeyboardHandler: KeyboardDelegate {
	static let shared = MainWindowKeyboardHandler()

	func keydown(_ event: NSEvent, in view: NSView) -> Bool {
		let key = KeyboardKey(with: event)
		let shortcuts = KeyboardShortcutStore.shared.effectiveShortcuts(for: .global)
		guard let matchingShortcut = KeyboardShortcut.findMatchingShortcut(in: shortcuts, key: key) else {
			return false
		}

		matchingShortcut.perform(with: view)
		return true
	}
}
