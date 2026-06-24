# In-app webview: window chrome, sidebar, URL overlay, and swipe

Date: 2026-06-24

Follow-up to `2026-06-24-in-app-webview-panel-design.md`. The in-app browser
panel works; this refines its presentation and adds a swipe entry point.

## Goals

1. **Toolbar swap.** While the webview is open, hide the article toolbar
   buttons (mark read, star, share, reader view, open in browser, next-unread,
   mark-all-read, read filter) and show browser nav buttons (‹ Article, back,
   forward, reload, Open in Safari) in the same window toolbar. Restore on
   close. (Currently the browser controls render inside the detail pane and are
   visually occluded by the window toolbar.)
2. **URL bottom-right.** Move the current-URL display out of the panel's top
   toolbar to a small overlay at the bottom-right of the webview.
3. **Sidebar collapse.** Collapse the feed-list sidebar when the webview opens;
   restore its previous state when the webview closes.
4. **Swipe to open.** A right-to-left swipe on the article reader view opens the
   current article's link in the webview. A left-to-right swipe while browsing
   returns to the article.

## Background (verified in code)

- The window toolbar is built in code in `MainWindowController` via
  `NSToolbarDelegate` (`toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`,
  `toolbarAllowedItemIdentifiers`, `toolbarDefaultItemIdentifiers`), validated
  through `validateUserInterfaceItem(_:)`; revalidate via `makeToolbarValidate()`
  → `window?.toolbar?.validateVisibleItems()`. `autosavesConfiguration = true`.
- The three panes are an `NSSplitViewController`; `MainWindowController` exposes
  `sidebarSplitViewItem` and already reads/writes `.isCollapsed` for state
  restoration (`savableState()`, `restoreSplitViewState(from:)`).
- `MainWindowController` is the coordinator: sidebar → timeline → detail.
- The article reader is `DetailWebView` (a `WKWebView` subclass) inside
  `DetailWebViewController` inside `DetailViewController`.
- The current article's external link is `Article.preferredURL` /
  `preferredLink` (`Shared/Extensions/ArticleUtilities.swift`), already used by
  `openArticleInBrowser(_:)`.

## Architecture: lift coordination to MainWindowController

The browser web view stays inside the detail pane, but session
*coordination* moves up to `MainWindowController`, because opening/closing now
affects the toolbar and the sidebar — both owned there.

Two entry points, one path:
- In-content link click: `DetailWebViewController` → `DetailViewController` →
  (delegate) `MainWindowController.showInAppBrowser(url:)`.
- Right-to-left swipe on the reader: resolve the article's `preferredURL` →
  `MainWindowController.showInAppBrowser(url:)`.

`showInAppBrowser(url:)`:
1. Save `wasSidebarCollapsed`; collapse the sidebar
   (`sidebarSplitViewItem?.animator().isCollapsed = true`).
2. Switch the toolbar to browser mode.
3. `detailViewController.showBrowser(url:)` (swaps the detail content view).

`closeInAppBrowser()` reverses in order: restore the toolbar, restore the
sidebar to `wasSidebarCollapsed`, `detailViewController.dismissBrowser()`.
Triggered by ‹ Article, Esc, or a left-to-right swipe.

`DetailViewController` keeps owning the browser controller and exposes thin
controls used by the toolbar actions: `browserGoBack()`, `browserGoForward()`,
`browserReload()`, `browserOpenInSafari()`, `browserCanGoBack`,
`browserCanGoForward`. It gains a `weak delegate: DetailViewControllerDelegate`
(implemented by `MainWindowController`) with
`detailViewControllerDidRequestInAppBrowser(_:url:)` and
`detailViewControllerDidRequestArticle(_:)`. The `LinkOpenDecider` routing is
unchanged.

## Toolbar swap

- Add item identifiers: `browserGoArticle`, `browserGoBack`, `browserGoForward`,
  `browserReload`, `browserOpenInSafari`. Vend them from the delegate with
  actions on `MainWindowController` that forward to `detailViewController`.
- Enter browser mode: set `autosavesConfiguration = false`; remove the
  article-related items by index (`toolbar.removeItem(at:)`); insert the browser
  items (`toolbar.insertItem(withItemIdentifier:at:)`). Keep neutral items
  (sidebar toggle, refresh, flexible space, search).
- Exit: remove browser items, reinsert the article items, restore
  `autosavesConfiguration = true`.
- `validateUserInterfaceItem(_:)` returns `browserCanGoBack` /
  `browserCanGoForward` for the back/forward items; the browser controller posts
  a notification on `canGoBack`/`canGoForward` changes so `makeToolbarValidate()`
  re-runs.

## URL overlay

`DetailBrowserViewController` drops its top toolbar (the actions live in the
window toolbar now). Layout becomes the `WKWebView` filling the pane, plus a
URL `NSTextField` (label style) pinned bottom-right with an 8pt inset, a
translucent rounded background, `lineBreakMode = .byTruncatingTail`, and a max
width. Updated from the existing `url` KVO. Hidden when empty.

## Swipe gesture

Override `swipe(with event: NSEvent)` on `DetailWebView`:
- `event.deltaX < 0` (right-to-left) → notify controller to open the current
  article's `preferredURL`.
- `event.deltaX > 0` (left-to-right) → notify controller to return to article
  (no-op if not browsing).

`swipe(with:)` is the standard AppKit page-swipe hook and honors the trackpad
"swipe between pages" setting. The article reader has no web history, so there's
no collision. Extract the direction logic into a pure helper for testing.
Runtime fallback if `swipe(with:)` proves unreliable on `WKWebView`:
`scrollWheel(with:)` + `NSEvent.trackSwipeEvent`.

## Testing

- Keep the `LinkOpenDecider` tests.
- Add a pure `SwipeDecision` helper: `(deltaX, isBrowsing) → .openWeb |
  .returnToArticle | .ignore`, unit-tested.
- Manual: toolbar swaps and restores; back/forward enablement tracks history;
  sidebar collapses on open and restores on close (including the case where it
  was already collapsed); URL shows bottom-right and truncates; right-to-left
  swipe opens the article in the webview; left-to-right returns.

## Out of scope (YAGNI)

- iOS. Editable address bar. Tabs. Multiple concurrent browser panels.
- Persisting browser state across app relaunches.
