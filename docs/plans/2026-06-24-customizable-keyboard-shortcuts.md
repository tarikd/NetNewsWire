# Customizable Keyboard Shortcuts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users remap NetNewsWire's plist-based reading/navigation keyboard shortcuts from a new Keyboard preferences pane, with a record-a-keystroke editor and warn-and-reassign conflict handling.

**Architecture:** A `KeyboardShortcutStore` (Mac) merges per-context plist *defaults* with user *overrides* (in UserDefaults) into the effective `Set<KeyboardShortcut>` each keyboard delegate uses. A programmatic `KeyboardPreferencesViewController` with a `ShortcutRecorderView` edits bindings through the store; the store caches effective sets and invalidates on change, so edits take effect live.

**Tech Stack:** Swift, AppKit, XCTest. RSCore module (`Modules/RSCore`), Mac app target. Files are target members by folder (synchronized groups) — no `project.pbxproj` edits.

**Design doc:** `docs/plans/2026-06-24-customizable-keyboard-shortcuts-design.md`

**Branch:** `feature/customizable-keyboard-shortcuts` (off `main`).

**Build / test (signing disabled):**
- Build: `xcodebuild build -project NetNewsWire.xcodeproj -scheme NetNewsWire -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- Test: `xcodebuild test -project NetNewsWire.xcodeproj -scheme NetNewsWire -destination 'platform=macOS' -only-testing:NetNewsWireTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`

**Git rule:** no AI/Claude/Co-Authored-By attribution in commits.

**Verified facts:**
- `Modules/RSCore/Sources/RSCore/AppKit/Keyboard.swift`: `KeyboardKey` (fields `integerValue`, `shiftKeyDown`, `optionKeyDown`, `commandKeyDown`, `controlKeyDown`; internal memberwise `init`; public `init(with: NSEvent)`, `init?(dictionary:)`). `KeyboardShortcut` (`key`, `actionString`; only `init?(dictionary:)`; `perform(with:)`; static `findMatchingShortcut(in:key:)`).
- Delegates load a plist into a `let` set and dispatch: `Mac/MainWindow/Keyboard/MainWindowKeyboardHandler.swift` (singleton `.shared`, `globalShortcuts`), `Mac/MainWindow/Timeline/Keyboard/TimelineKeyboardDelegate.swift`, `Mac/MainWindow/Sidebar/Keyboard/SidebarKeyboardDelegate.swift`, `Mac/MainWindow/Detail/Keyboard/DetailKeyboardDelegate.swift`. Sidebar/Timeline/Detail call `MainWindowKeyboardHandler.shared.keydown` first.
- Plists: `Shared/Resources/{Global,Sidebar,Timeline,Detail}KeyboardShortcuts.plist`.
- Preferences: `Mac/Preferences/PreferencesWindowController.swift` (toolbar items General/Accounts/Advanced; panes from `Preferences.storyboard`).

---

## Task 1: Public initializers in RSCore (TDD)

Allow building shortcuts programmatically.

**Files:**
- Modify: `Modules/RSCore/Sources/RSCore/AppKit/Keyboard.swift`
- Test: `Tests/NetNewsWireTests/KeyboardShortcutBuildingTests.swift`

**Step 1: Failing test**
```swift
import XCTest
import RSCore
@testable import NetNewsWire

final class KeyboardShortcutBuildingTests: XCTestCase {
	func testBuildShortcutFromKey() {
		let key = KeyboardKey(integerValue: Int(Character("n").asciiValue!), shiftKeyDown: false, optionKeyDown: false, commandKeyDown: true, controlKeyDown: false)
		let shortcut = KeyboardShortcut(key: key, actionString: "nextUnread:")
		XCTAssertEqual(shortcut.actionString, "nextUnread:")
		XCTAssertEqual(shortcut.key, key)
		XCTAssertTrue(key.commandKeyDown)
	}
}
```

**Step 2: Run — expect FAIL** (`init` inaccessible).

**Step 3: Implement** — in `Keyboard.swift` make the `KeyboardKey` memberwise init `public`:
```swift
	public init(integerValue: Int, shiftKeyDown: Bool, optionKeyDown: Bool, commandKeyDown: Bool, controlKeyDown: Bool) {
```
and add to `KeyboardShortcut`:
```swift
	public init(key: KeyboardKey, actionString: String) {
		self.key = key
		self.actionString = actionString
	}
```

**Step 4: Run — expect PASS.**

**Step 5: Commit**
```bash
git add Modules/RSCore/Sources/RSCore/AppKit/Keyboard.swift Tests/NetNewsWireTests/KeyboardShortcutBuildingTests.swift
git commit -m "Add public initializers for building keyboard shortcuts"
```

---

## Task 2: KeyboardKey ⇆ dictionary encoding (TDD)

A codec to persist a `KeyboardKey` in UserDefaults.

**Files:**
- Create: `Mac/Preferences/Keyboard/KeyboardKeyCoder.swift`
- Test: `Tests/NetNewsWireTests/KeyboardKeyCoderTests.swift`

**Step 1: Failing test**
```swift
import XCTest
import RSCore
@testable import NetNewsWire

final class KeyboardKeyCoderTests: XCTestCase {
	func testRoundTrip() {
		let key = KeyboardKey(integerValue: 110, shiftKeyDown: true, optionKeyDown: false, commandKeyDown: true, controlKeyDown: false)
		let dict = KeyboardKeyCoder.dictionary(from: key)
		let decoded = KeyboardKeyCoder.key(from: dict)
		XCTAssertEqual(decoded, key)
	}

	func testSpecialKeyValuePreserved() {
		let up = KeyboardKey(integerValue: NSUpArrowFunctionKey, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		XCTAssertEqual(KeyboardKeyCoder.key(from: KeyboardKeyCoder.dictionary(from: up)), up)
	}

	func testInvalidDictionaryReturnsNil() {
		XCTAssertNil(KeyboardKeyCoder.key(from: [:]))
	}
}
```

**Step 3: Implement** `Mac/Preferences/Keyboard/KeyboardKeyCoder.swift`:
```swift
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
```

**Step 5: Commit** `"Add KeyboardKey UserDefaults codec"`.

---

## Task 3: KeyboardShortcutStore (TDD for the pure logic)

**Files:**
- Create: `Mac/Preferences/Keyboard/KeyboardShortcutStore.swift`
- Test: `Tests/NetNewsWireTests/KeyboardShortcutStoreTests.swift`

Design:
```swift
import AppKit
import RSCore

@MainActor final class KeyboardShortcutStore {

	static let shared = KeyboardShortcutStore()

	enum Context: String, CaseIterable {
		case global, sidebar, timeline, detail
		var plistName: String {
			switch self {
			case .global: return "GlobalKeyboardShortcuts"
			case .sidebar: return "SidebarKeyboardShortcuts"
			case .timeline: return "TimelineKeyboardShortcuts"
			case .detail: return "DetailKeyboardShortcuts"
			}
		}
		var displayName: String {
			switch self {
			case .global: return NSLocalizedString("Everywhere", comment: "")
			case .sidebar: return NSLocalizedString("Sidebar", comment: "")
			case .timeline: return NSLocalizedString("Timeline", comment: "")
			case .detail: return NSLocalizedString("Article", comment: "")
			}
		}
	}

	struct Command: Equatable {
		let title: String
		let action: String
		let defaultKey: KeyboardKey
		var currentKey: KeyboardKey?   // nil == unbound
	}

	static let didChangeNotification = Notification.Name("KeyboardShortcutsDidChange")
	private static let defaultsKey = "userKeyboardShortcuts"

	// Pure merge — unit-testable, no Bundle/UserDefaults.
	static func mergedCommands(defaults: [Command], overrides: [String: KeyboardKey?]) -> [Command] {
		defaults.map { d in
			var c = d
			if let override = overrides[d.action] {   // present == user changed it (value may be nil == unbound)
				c.currentKey = override
			}
			return c
		}
	}

	// Conflict resolution — unit-testable. Returns the action that must be unbound (if any).
	static func conflictingAction(for key: KeyboardKey, assigningTo action: String, in commands: [Command]) -> String? {
		for c in commands where c.action != action {
			if c.currentKey == key { return c.action }
		}
		return nil
	}

	func effectiveShortcuts(for context: Context) -> Set<KeyboardShortcut> {
		let commands = self.commands(for: context)
		return Set(commands.compactMap { c in c.currentKey.map { KeyboardShortcut(key: $0, actionString: c.action) } })
	}

	func commands(for context: Context) -> [Command] { /* load plist defaults + apply stored overrides via mergedCommands */ }
	@discardableResult func setBinding(_ key: KeyboardKey, forAction action: String, in context: Context) -> String? { /* resolve conflict (unbind other), save override, invalidate cache, post notification; return reassigned title */ }
	func clearBinding(forAction action: String, in context: Context) { /* store nil override */ }
	func restoreDefaults() { /* remove the defaultsKey, invalidate, post */ }
}
```

Implementation notes:
- `commands(for:)`: load the context plist (same as the delegates do: `Bundle.main.path(forResource:context.plistName, ofType:"plist")`), build `[Command]` (title from `title` or a fallback derived from the action; defaultKey from `KeyboardKey(dictionary:)`), then apply overrides read from UserDefaults (`[contextRaw: [action: keyDict|NSNull]]`) via `mergedCommands`.
- Cache the merged `[Command]` per context; clear on any mutation.
- Overrides persistence: `UserDefaults.standard.dictionary(forKey: defaultsKey)` shaped `[context.rawValue: [action: Any]]` where value is a `KeyboardKeyCoder` dictionary, or `NSNull`/absent. A present `NSNull` means unbound; absent means default.

**Tests (pure functions — no Bundle needed):**
```swift
final class KeyboardShortcutStoreTests: XCTestCase {
	private func cmd(_ action: String, _ ch: Character, current: KeyboardKey?) -> KeyboardShortcutStore.Command {
		let key = KeyboardKey(integerValue: Int(ch.asciiValue!), shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		return .init(title: action, action: action, defaultKey: key, currentKey: current ?? key)
	}

	func testOverrideReplacesDefault() {
		let n = KeyboardKey(integerValue: 110, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		let r = KeyboardKey(integerValue: 114, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		let defaults = [KeyboardShortcutStore.Command(title: "Next", action: "next:", defaultKey: n, currentKey: n)]
		let merged = KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: ["next:": r])
		XCTAssertEqual(merged[0].currentKey, r)
	}

	func testUnbindOverride() {
		let n = KeyboardKey(integerValue: 110, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		let defaults = [KeyboardShortcutStore.Command(title: "Next", action: "next:", defaultKey: n, currentKey: n)]
		let merged = KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: ["next:": KeyboardKey?.none])
		XCTAssertNil(merged[0].currentKey)
	}

	func testUntouchedKeepsDefault() {
		let n = KeyboardKey(integerValue: 110, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		let defaults = [KeyboardShortcutStore.Command(title: "Next", action: "next:", defaultKey: n, currentKey: n)]
		XCTAssertEqual(KeyboardShortcutStore.mergedCommands(defaults: defaults, overrides: [:])[0].currentKey, n)
	}

	func testConflictDetected() {
		let key = KeyboardKey(integerValue: 110, shiftKeyDown: false, optionKeyDown: false, commandKeyDown: false, controlKeyDown: false)
		let commands = [cmd("a:", "n", current: key), cmd("b:", "r", current: nil)]
		XCTAssertEqual(KeyboardShortcutStore.conflictingAction(for: key, assigningTo: "b:", in: commands), "a:")
		XCTAssertNil(KeyboardShortcutStore.conflictingAction(for: key, assigningTo: "a:", in: commands))
	}
}
```
> Note: `overrides: [String: KeyboardKey?]` uses a present-but-nil value to mean "unbound"; the test `["next:": KeyboardKey?.none]` exercises that. In `mergedCommands`, detect presence with `overrides.index(forKey:)` / `overrides.keys.contains` rather than optional-chaining, so a stored nil is honored.

**Commit** `"Add keyboard shortcut store with override merge and conflict resolution"`.

---

## Task 4: KeyboardKey display formatter (TDD)

**Files:**
- Create: `Mac/Preferences/Keyboard/KeyboardKey+DisplayString.swift`
- Test: `Tests/NetNewsWireTests/KeyboardKeyDisplayTests.swift`

`displayString` maps modifiers to `⌃⌥⇧⌘` (in that conventional order) + the key: special values (space→"Space", arrows→`←↑→↓`, return→"↩", tab→"⇥", delete→"⌫") else the uppercased character.

**Tests:**
```swift
func testPlainLetter() { XCTAssertEqual(KeyboardKey(integerValue: 110, shiftKeyDown:false,optionKeyDown:false,commandKeyDown:false,controlKeyDown:false).displayString, "N") }
func testCommandLetter() { XCTAssertEqual(KeyboardKey(integerValue: 110, shiftKeyDown:false,optionKeyDown:false,commandKeyDown:true,controlKeyDown:false).displayString, "⌘N") }
func testSpace() { XCTAssertEqual(KeyboardKey(integerValue: 32, shiftKeyDown:false,optionKeyDown:false,commandKeyDown:false,controlKeyDown:false).displayString, "Space") }
func testArrow() { XCTAssertEqual(KeyboardKey(integerValue: NSRightArrowFunctionKey, shiftKeyDown:false,optionKeyDown:false,commandKeyDown:false,controlKeyDown:false).displayString, "→") }
```
Implement as `extension KeyboardKey { var displayString: String { ... } }` in the Mac target (KeyboardKey is public from RSCore). **Commit** `"Add display strings for keyboard keys"`.

---

## Task 5: Drive the keyboard delegates from the store

Replace the four delegates' direct plist loads with the store, so custom bindings dispatch and edits apply live.

**Files:**
- Modify: `Mac/MainWindow/Keyboard/MainWindowKeyboardHandler.swift`
- Modify: `Mac/MainWindow/Timeline/Keyboard/TimelineKeyboardDelegate.swift`
- Modify: `Mac/MainWindow/Sidebar/Keyboard/SidebarKeyboardDelegate.swift`
- Modify: `Mac/MainWindow/Detail/Keyboard/DetailKeyboardDelegate.swift`

For each, drop the stored `let ... = Set(...)` plist load and query the store in `keydown`:
```swift
// MainWindowKeyboardHandler.keydown:
let key = KeyboardKey(with: event)
let shortcuts = KeyboardShortcutStore.shared.effectiveShortcuts(for: .global)
guard let matching = KeyboardShortcut.findMatchingShortcut(in: shortcuts, key: key) else { return false }
matching.perform(with: view); return true
```
and `.timeline` / `.sidebar` / `.detail` for the others (keeping the "consult `MainWindowKeyboardHandler.shared` first" calls). The store caches per context, so this stays cheap. Remove the now-unused init plist loading.

**Build**; **run unit tests**. Expect pass. **Commit** `"Load keyboard shortcuts through the customizable store"`.

> After this task, shortcuts behave exactly as before (no overrides yet), now sourced from the store.

---

## Task 6: Keyboard preferences pane + recorder

**Files:**
- Create: `Mac/Preferences/Keyboard/ShortcutRecorderView.swift`
- Create: `Mac/Preferences/Keyboard/KeyboardPreferencesViewController.swift`
- Modify: `Mac/Preferences/PreferencesWindowController.swift`

`ShortcutRecorderView`: a focusable `NSView` (or `NSButton` subclass) showing the current `displayString` (or "Click to record"). On click → `acceptsFirstResponder`, becomes first responder, shows "Type shortcut…"; override `keyDown` → if Esc, cancel; else build `KeyboardKey(with: event)` and call `onRecord?(key)`. Expose `onRecord: ((KeyboardKey) -> Void)?` and a `clear` affordance.

`KeyboardPreferencesViewController`: programmatic (no storyboard scene). An `NSScrollView` + stack of sections, one per `KeyboardShortcutStore.Context` (`.allCases`), each titled `displayName`, listing `store.commands(for: context)`: row = command title + `ShortcutRecorderView` + ✕ clear button. Recording calls `store.setBinding(key, forAction:in:)`; if it returns a reassigned title, show an inline note and refresh that section. ✕ calls `store.clearBinding`. A **Restore Defaults** button calls `store.restoreDefaults()` and reloads. Reload the rows on `KeyboardShortcutStore.didChangeNotification`.

`PreferencesWindowController`: read the file to see how toolbar items map to view controllers. Add a `Keyboard` toolbar item (after Advanced) whose view controller is `KeyboardPreferencesViewController()` instantiated **in code** (not from `Preferences.storyboard`), so no storyboard surgery is needed. Use an SF Symbol like `keyboard` for the toolbar image and "Keyboard" as the label.

**Build.** Fix compile errors in these files. If wiring the toolbar item cleanly requires understanding the existing pattern, follow it exactly; if a storyboard edit seems unavoidable, STOP and ask. **Commit** `"Add a Keyboard preferences pane for remapping shortcuts"`.

---

## Task 7: Manual verification + final review

Build and run (`On My Mac` feed). Verify:
1. Preferences → **Keyboard** pane lists commands grouped by Everywhere / Sidebar / Timeline / Article with their current shortcuts.
2. Record a new key for **Next Unread** (e.g. `j`); without relaunch, `j` goes to the next unread and the old `n` no longer does.
3. Recording a key already used in that context clears it from the previous command and shows the note.
4. ✕ clears a binding (that command has no shortcut; verify the key does nothing).
5. **Restore Defaults** returns everything to the shipped shortcuts.
6. Relaunch → overrides persisted.
7. Cross-context: an arrow still means different things in sidebar vs timeline (no false conflict).

Document results, dispatch a final whole-branch review, and finish the branch.

## Notes for the implementer
- Files are target members by folder — no `project.pbxproj` edits. New files live under `Mac/Preferences/Keyboard/`; tests under `Tests/NetNewsWireTests/`.
- `KeyboardShortcutStore` and the recorder are `@MainActor` (AppKit + the `@MainActor` `perform`).
- Keep dispatch and the plists unchanged; this feature only changes *which* set the delegates use and adds the editor.
- A stored override value of `nil` means "explicitly unbound" and must be distinguished from "no override" (absent key). Don't collapse the two.
