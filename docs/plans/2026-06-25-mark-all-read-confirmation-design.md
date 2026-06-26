# Mark All as Read — confirmation banner

## Goal

Before marking a whole timeline (or feed/folder) as read, show a confirmation
banner that slides down over the top of the timeline column. The user picks
**Mark All as Read** or **Cancel**, with Cancel as the safe default.

## Decisions

- **Scope:** every mark-all path confirms — the toolbar button, the keyboard
  shortcut (and its "go to next unread" variant), the timeline's per-feed
  context menu, and the sidebar's "Mark All as Read" context menu.
- **No opt-out:** always confirm. No preference, no "don't ask again", no
  unread-count threshold. Simplest and most protective.
- **Placement:** an overlay pinned to the top of the timeline column that
  floats over the first row or two of the list (it does not push the list
  down). Cancel is the default (Return), and Esc also cancels.

## Component

`Mac/MainWindow/Timeline/MarkAllAsReadConfirmationView.swift` — an
`NSVisualEffectView` (`.headerView` material, hairline bottom border) holding
the prompt "Mark all as read?" and two buttons: **Mark All as Read** and
**Cancel**. Cancel carries the Return key equivalent so it's the default; the
view overrides `cancelOperation(_:)` so Esc cancels too. Two callbacks
(confirm/cancel) report the choice.

`TimelineViewController` owns the overlay and exposes one entry point:

```swift
func confirmMarkAllAsRead(_ onConfirm: @escaping () -> Void)
```

It adds the banner as a subview of its root view, pinned leading/trailing/top
with a fixed height, starting offscreen above the top edge. Showing animates
the top constraint to 0 (~0.2s slide-down) and makes the banner first
responder; choosing either button animates it back up and removes it,
returning focus to the table. Only one banner exists at a time — calling again
while visible is a no-op.

## Wiring

Each trigger checks "is there anything to mark?" first (so an empty timeline or
already-read feed shows no banner), then wraps its existing mark-read call in
`confirmMarkAllAsRead { ... }`:

- **Toolbar + keyboard:** `MainWindowController.markAllAsRead(_:)` and
  `markAllAsReadAndGoToNextUnread(_:)` guard on `canMarkAllAsRead()` then wrap.
- **Timeline per-feed menu:** `markAllInFeedAsRead(_:)` keeps its
  `unreadArticles.isEmpty` guard, then wraps the command.
- **Sidebar menu:** `markObjectsReadFromContextualMenu(_:)` can't reach the
  timeline directly, so a new `SidebarDelegate.sidebarConfirmMarkAllAsRead(_:confirmed:)`
  is added; `MainWindowController` forwards it to
  `currentTimelineViewController.confirmMarkAllAsRead`. The banner appears in
  the adjacent timeline column.

Gating lives at these call sites, not inside the low-level
`markAllAsRead(completion:)` / `MarkStatusCommand`, so programmatic callers
(undo, restoration, future code) are never prompted or double-prompted.

## Files

- New: `Mac/MainWindow/Timeline/MarkAllAsReadConfirmationView.swift`
- Edit: `TimelineViewController.swift`, `MainWindowController.swift`,
  `TimelineViewController+ContextualMenus.swift`,
  `SidebarViewController.swift` (protocol),
  `SidebarViewController+ContextualMenus.swift`

File-system-synchronized groups mean no `project.pbxproj` changes for the new
file.

## Verification

Almost entirely AppKit view/animation work with no meaningful pure logic, so
verification is a clean build plus a manual pass of all four paths: banner
slides in; Cancel and Esc abort with nothing marked; Mark All as Read proceeds
exactly as before; an empty/already-read target shows no banner.
