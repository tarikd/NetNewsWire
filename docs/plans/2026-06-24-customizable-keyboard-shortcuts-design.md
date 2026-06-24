# Customizable keyboard shortcuts (macOS)

Date: 2026-06-24

## Goal

Let users remap NetNewsWire's reading/navigation keyboard shortcuts (the
single-key shortcuts loaded from the `*KeyboardShortcuts.plist` files) from a
new Keyboard preferences pane, with a record-a-keystroke editor and conflict
handling. Menu ⌘-command equivalents are out of scope.

## Background (verified in code)

- Shortcut definitions: `Shared/Resources/{Global,Sidebar,Timeline,Detail}KeyboardShortcuts.plist`.
  Each entry: `key` (e.g. `n`, `[space]`, `[uparrow]`), `action` (ObjC selector
  like `nextUnread:`), optional `title`, and `shift/option/command/controlModifier`
  booleans.
- `KeyboardKey` / `KeyboardShortcut` live in
  `Modules/RSCore/Sources/RSCore/AppKit/Keyboard.swift`. `KeyboardKey(with: NSEvent)`
  turns an event into `integerValue` + four modifier flags; `KeyboardKey(dictionary:)`
  parses the plist format. `KeyboardShortcut.perform(with:)` dispatches via
  `NSApplication.shared.sendAction`.
- Four delegates load a context's plist directly and dispatch:
  `MainWindowKeyboardHandler` (global), `SidebarKeyboardDelegate`,
  `TimelineKeyboardDelegate`, `DetailKeyboardDelegate`. The sidebar/timeline/detail
  delegates consult the global handler first, then their own set.
- Preferences is a toolbar window (`PreferencesWindowController`): General,
  Accounts, Advanced. Panes come from `Preferences.storyboard`.
- No existing shortcut customization; `AppDefaults` has no keyboard keys.

## Decisions

- **Scope:** the plist reading/nav shortcuts across all four contexts. Menu
  ⌘-equivalents untouched. macOS only. Single keystroke per command (no chords).
- **Editing:** click a recorder, press the desired key (single key or combo).
- **Conflicts:** warn and reassign — binding a combo already used in the *same*
  context clears it from the previous command. Cross-context duplicates allowed.

## Architecture

### KeyboardShortcutStore (new, Mac)
Owns the effective shortcuts for each context:
- Loads the plist **defaults** for a context (as the delegates do today).
- Reads user **overrides** from `UserDefaults`.
- `effectiveShortcuts(for context:) -> Set<KeyboardShortcut>`: defaults with
  overrides applied (override replaces a command's key; a "none" override removes
  it; untouched commands keep their default).
- `commands(for:) -> [Command]`: the editable list for the UI — title, action
  selector, default binding, current binding.
- `setBinding(_:forAction:in:)` / `clearBinding(...)` / `restoreDefaults()`:
  mutate overrides, save, and post `.KeyboardShortcutsDidChange`.

Overrides persist under one `UserDefaults` key (`userKeyboardShortcuts`) shaped
`[contextName: [actionSelector: binding]]`; a binding encodes the `KeyboardKey`
fields (integer value + four modifier booleans) or a sentinel for "unbound".
Keyed by action selector so it's stable across upstream key changes.

### Wiring into the delegates
The four delegates stop reading the plist directly and ask
`KeyboardShortcutStore` for their context's effective set. They observe
`.KeyboardShortcutsDidChange` and rebuild, so edits take effect live (no
relaunch). Dispatch is unchanged.

## Preferences pane

`KeyboardPreferencesViewController` (new toolbar item after Advanced). A scroll
list of commands grouped by context — Everywhere (global), Sidebar, Timeline,
Article (detail) — using each plist entry's `title`. Each row: command name, a
`ShortcutRecorderView`, and a ✕ to clear. A **Restore Defaults** button.

`ShortcutRecorderView`: a focusable `NSView`. Click → "Type shortcut…" → the next
`keyDown` becomes a `KeyboardKey` via `KeyboardKey(with:)`. Esc cancels; ✕ clears.
A `KeyboardKey → String` formatter renders the binding ("⌥⌘N", "Space", "→", "⇧;").

Conflict: on record, the store checks the same context's effective bindings for
that key; if another command has it, that command is unbound (its row clears)
with an inline "Was used by '<command>'." note.

## Testing

Unit-testable (no AppKit UI):
- Override merge: defaults + overrides → effective set (replace / remove / keep).
- Encoding round-trip: `KeyboardKey` → UserDefaults dict → `KeyboardKey`,
  including special keys and all four modifiers.
- Conflict resolution: existing bindings + new (action, key) → which command is
  reassigned.
- Display formatting: `KeyboardKey` → label.

Manual: Preferences → Keyboard; remap "Next Unread", confirm live; trigger a
conflict and see the previous command clear; clear a binding; Restore Defaults;
relaunch and confirm persistence.

## Out of scope (YAGNI)

Menu ⌘-command customization; iOS; multi-key chords; import/export of shortcut
sets; per-feed or per-account shortcuts.
