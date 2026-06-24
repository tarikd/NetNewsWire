# Webview Window Chrome, Sidebar & Swipe — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish the in-app webview panel: swap the window toolbar to browser controls while browsing, move the URL to a bottom-right overlay, collapse the sidebar on open / restore on close, and open the current article in the webview via a right-to-left swipe on the reader (left-to-right returns).

**Architecture:** Lift browser-session *coordination* from `DetailViewController` up to `MainWindowController` (which owns the toolbar and sidebar). The web view stays in the detail pane. A new `DetailViewControllerDelegate` (implemented by `MainWindowController`) carries "open this URL in the browser" and "return to the article" up; `MainWindowController` then drives the sidebar + toolbar and tells `DetailViewController` to show/hide the browser content view. Toolbar swapping is done by replacing the whole `NSWindow.toolbar` with a dedicated browser toolbar, not by mutating items.

**Tech Stack:** AppKit, WebKit, Swift, XCTest. Project `NetNewsWire.xcodeproj`, scheme `NetNewsWire`, test target `NetNewsWireTests`. Files are target members by folder (file-system-synchronized groups) — no `project.pbxproj` edits.

**Design doc:** `docs/plans/2026-06-24-webview-window-chrome-design.md`

**Build / test commands (signing disabled in this environment):**
- Build: `xcodebuild build -project NetNewsWire.xcodeproj -scheme NetNewsWire -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
- Test: `xcodebuild test -project NetNewsWire.xcodeproj -scheme NetNewsWire -destination 'platform=macOS' -only-testing:NetNewsWireTests CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`

**Git rule:** No AI/Claude/Co-Authored-By attribution in any commit message.

**Current state (already on the branch):**
- `Mac/MainWindow/Detail/LinkOpenDecision.swift` — routing decision.
- `Mac/MainWindow/Detail/DetailBrowserViewController.swift` — browser VC, currently with its own top toolbar (Article/back/forward/reload/address/Safari), KVO on canGoBack/canGoForward/url, `load(_:)`, `stopMediaPlayback()`, `focusWebView()`, `cancelOperation`, error page. Delegate `DetailBrowserViewControllerDelegate.detailBrowserViewControllerDidRequestArticle(_:)`.
- `Mac/MainWindow/Detail/DetailWebViewController.swift` — routes `.linkActivated` + window.open through `LinkOpenDecider` to `delegate?.openInAppBrowser(_:url:)`.
- `Mac/MainWindow/Detail/DetailViewController.swift` — creates a fresh `DetailBrowserViewController` per session, swaps `containerView.contentView`, `dismissBrowserIfNeeded()`, conforms to both detail delegates.

---

## Task 1: Swipe-direction decision (TDD)

A pure helper deciding what a horizontal swipe means, so the gesture logic is testable without AppKit events.

**Files:**
- Create: `Mac/MainWindow/Detail/SwipeDecision.swift`
- Test: `Tests/NetNewsWireTests/SwipeDecisionTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NetNewsWire

final class SwipeDecisionTests: XCTestCase {

	func testRightToLeftWhileReadingOpensWeb() {
		XCTAssertEqual(SwipeDecider.action(deltaX: -1.0, isBrowsing: false), .openWeb)
	}

	func testLeftToRightWhileBrowsingReturns() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 1.0, isBrowsing: true), .returnToArticle)
	}

	func testRightToLeftWhileBrowsingIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: -1.0, isBrowsing: true), .ignore)
	}

	func testLeftToRightWhileReadingIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 1.0, isBrowsing: false), .ignore)
	}

	func testZeroDeltaIsIgnored() {
		XCTAssertEqual(SwipeDecider.action(deltaX: 0.0, isBrowsing: false), .ignore)
		XCTAssertEqual(SwipeDecider.action(deltaX: 0.0, isBrowsing: true), .ignore)
	}
}
```

**Step 2: Run the test, expect FAIL** (`SwipeDecider` not in scope).
`xcodebuild test ... -only-testing:NetNewsWireTests/SwipeDecisionTests ...`

**Step 3: Implement**

```swift
//
//  SwipeDecision.swift
//  NetNewsWire
//
//  Maps a horizontal swipe on the detail pane to an action: open the current
//  article in the in-app webview (right-to-left while reading) or return to the
//  article (left-to-right while browsing).
//

import Foundation

enum SwipeAction: Equatable {
	case openWeb
	case returnToArticle
	case ignore
}

enum SwipeDecider {

	/// AppKit reports a right-to-left page swipe as a negative deltaX.
	static func action(deltaX: CGFloat, isBrowsing: Bool) -> SwipeAction {
		if deltaX < 0 {
			return isBrowsing ? .ignore : .openWeb
		}
		if deltaX > 0 {
			return isBrowsing ? .returnToArticle : .ignore
		}
		return .ignore
	}
}
```

**Step 4: Run the test, expect PASS** (5 tests).

**Step 5: Commit**
```bash
git add Mac/MainWindow/Detail/SwipeDecision.swift Tests/NetNewsWireTests/SwipeDecisionTests.swift
git commit -m "Add swipe-direction decision for the reader pane"
```

---

## Task 2: Restructure DetailBrowserViewController (URL overlay + public nav API)

Remove the in-pane top toolbar (controls move to the window toolbar in Task 4) and add a bottom-right URL overlay. Expose a public navigation API and a notification when nav state changes so the window toolbar can revalidate.

**Files:**
- Modify: `Mac/MainWindow/Detail/DetailBrowserViewController.swift`

**Step 1: Replace the file** with this version (keeps the web view, KVO, error handling, Esc; drops the toolbar; adds the bottom-right URL label and public API):

```swift
//
//  DetailBrowserViewController.swift
//  NetNewsWire
//
//  An in-app web browser that replaces the article detail pane when the user
//  opens a link. Owns its own clean WKWebView. Navigation controls live in the
//  window toolbar (see MainWindowController); this view shows the page and a
//  small current-URL overlay in the bottom-right corner.
//

import AppKit
@preconcurrency import WebKit
import RSWeb

extension Notification.Name {
	static let DetailBrowserNavigationStateDidChange = Notification.Name("DetailBrowserNavigationStateDidChange")
}

@MainActor protocol DetailBrowserViewControllerDelegate: AnyObject {
	/// The user asked to return to the article (Esc).
	func detailBrowserViewControllerDidRequestArticle(_ controller: DetailBrowserViewController)
}

final class DetailBrowserViewController: NSViewController {

	weak var delegate: DetailBrowserViewControllerDelegate?

	private var webView: WKWebView!
	private let urlLabel = NSTextField(labelWithString: "")
	private var urlContainer: NSView!
	private var observations: [NSKeyValueObservation] = []

	var canGoBack: Bool { webView?.canGoBack ?? false }
	var canGoForward: Bool { webView?.canGoForward ?? false }
	var currentURL: URL? { webView?.url }

	override func loadView() {
		let configuration = WKWebViewConfiguration()
		webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.translatesAutoresizingMaskIntoConstraints = false
		if let userAgent = UserAgent.fromInfoPlist() {
			webView.customUserAgent = userAgent
		}

		let container = NSView()
		container.addSubview(webView)

		let overlay = makeURLOverlay()
		container.addSubview(overlay)

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: container.topAnchor),
			webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

			overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
			overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
			overlay.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.7)
		])

		view = container

		observeWebView()
	}

	// MARK: - API

	func load(_ url: URL) {
		webView.load(URLRequest(url: url))
		setURLText(url.absoluteString)
	}

	func focusWebView() {
		view.window?.makeFirstResponder(webView)
	}

	func stopMediaPlayback() {
		webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(m => m.pause());", completionHandler: nil)
	}

	func goBack() { webView.goBack() }
	func goForward() { webView.goForward() }
	func reload() { webView.reload() }

	func openInDefaultBrowser() {
		guard let url = webView.url else { return }
		Browser.open(url.absoluteString, invertPreference: false)
	}

	override func cancelOperation(_ sender: Any?) {
		// Esc returns to the article.
		delegate?.detailBrowserViewControllerDidRequestArticle(self)
	}

	// MARK: - Private

	private func makeURLOverlay() -> NSView {
		urlLabel.lineBreakMode = .byTruncatingTail
		urlLabel.textColor = .secondaryLabelColor
		urlLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		urlLabel.translatesAutoresizingMaskIntoConstraints = false

		let box = NSVisualEffectView()
		box.material = .hudWindow
		box.blendingMode = .withinWindow
		box.state = .active
		box.wantsLayer = true
		box.layer?.cornerRadius = 4
		box.translatesAutoresizingMaskIntoConstraints = false
		box.addSubview(urlLabel)

		NSLayoutConstraint.activate([
			urlLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
			urlLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3),
			urlLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
			urlLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8)
		])

		urlContainer = box
		box.isHidden = true
		return box
	}

	private func setURLText(_ text: String?) {
		let value = text ?? ""
		urlLabel.stringValue = value
		urlContainer?.isHidden = value.isEmpty
	}

	private func observeWebView() {
		observations = [
			webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
				Task { @MainActor in self?.postNavigationStateChange() }
			},
			webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
				Task { @MainActor in self?.postNavigationStateChange() }
			},
			webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
				Task { @MainActor in self?.setURLText(webView.url?.absoluteString) }
			}
		]
	}

	private func postNavigationStateChange() {
		NotificationCenter.default.post(name: .DetailBrowserNavigationStateDidChange, object: self)
	}
}

// MARK: - WKNavigationDelegate

extension DetailBrowserViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		showError(error)
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		showError(error)
	}

	private func showError(_ error: Error) {
		let nsError = error as NSError
		if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
			return
		}
		if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
			return
		}

		let message = nsError.localizedDescription
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
		let html = "<body style=\"font: -apple-system; color: #888; padding: 2em;\">Could not load this page.<br><br>\(message)</body>"
		webView.loadHTMLString(html, baseURL: nil)
	}
}
```

**Step 2: Build** with the signing-disabled command. Expect failures ONLY in `DetailViewController.swift` if it referenced removed APIs (it calls `load`, `focusWebView`, `stopMediaPlayback` — all retained, so it should still build). Expect `** BUILD SUCCEEDED **`. If `DetailViewController` referenced the old toolbar, fix in Task 3, not here.

**Step 3: Run all unit tests** — expect pass.

**Step 4: Commit**
```bash
git add Mac/MainWindow/Detail/DetailBrowserViewController.swift
git commit -m "Move browser controls out of the pane and show the URL bottom-right"
```

---

## Task 3: Swipe gesture on the reader view

Add a `swipe(with:)` override to the article web view and forward it up through `DetailWebViewController` to `DetailViewController`.

**Files:**
- Modify: `Mac/MainWindow/Detail/DetailWebView.swift`
- Modify: `Mac/MainWindow/Detail/DetailWebViewController.swift`
- Modify: `Mac/MainWindow/Detail/DetailViewController.swift`

**Step 1: `DetailWebView.swift`** — read it first. Add a swipe handler hook:
```swift
	var swipeHandler: ((CGFloat) -> Void)?

	override func swipe(with event: NSEvent) {
		swipeHandler?(event.deltaX)
	}
```
(If `DetailWebView` is shared by the search detail too, that's fine — the handler is only set by the controller that wants it.)

**Step 2: `DetailWebViewController.swift`**
- Add to `DetailWebViewControllerDelegate`:
```swift
	func detailWebViewController(_: DetailWebViewController, didSwipeWithDeltaX deltaX: CGFloat)
```
- In `loadView()`, after `webView` is created and configured, set:
```swift
		webView.swipeHandler = { [weak self] deltaX in
			guard let self else { return }
			self.delegate?.detailWebViewController(self, didSwipeWithDeltaX: deltaX)
		}
```
- Add a helper exposing the current article's URL (used by the coordinator):
```swift
	var currentArticleURL: URL? {
		article?.preferredURL
	}
```
(`article` already exists on this controller; `preferredURL` is on `Article` via `Shared/Extensions/ArticleUtilities.swift`. Confirm `import Articles` is present — it is.)

**Step 3: `DetailViewController.swift`** — implement the new delegate method. For now, translate the swipe into the existing open/dismiss behavior so the build stays green before Task 4 lifts coordination:
```swift
	func detailWebViewController(_ detailWebViewController: DetailWebViewController, didSwipeWithDeltaX deltaX: CGFloat) {
		switch SwipeDecider.action(deltaX: deltaX, isBrowsing: isShowingBrowser) {
		case .openWeb:
			if let url = detailWebViewController.currentArticleURL {
				openInAppBrowser(detailWebViewController, url: url)
			}
		case .returnToArticle:
			dismissBrowserIfNeeded()
			focus()
		case .ignore:
			break
		}
	}
```

**Step 4: Build** — expect `** BUILD SUCCEEDED **`. **Run unit tests** — expect pass.

**Step 5: Commit**
```bash
git add Mac/MainWindow/Detail/DetailWebView.swift Mac/MainWindow/Detail/DetailWebViewController.swift Mac/MainWindow/Detail/DetailViewController.swift
git commit -m "Open the article in the webview with a right-to-left swipe"
```

> After this task the swipe works and the panel still shows (without window-toolbar controls or sidebar collapse yet). Those arrive in Task 4.

---

## Task 4: Lift coordination to MainWindowController (toolbar swap + sidebar)

This is the largest task; it spans `DetailViewController` and `MainWindowController` and must be **one commit** to keep the build green.

**Files:**
- Modify: `Mac/MainWindow/Detail/DetailViewController.swift`
- Modify: `Mac/MainWindow/MainWindowController.swift`

### 4A — `DetailViewController`: delegate up, expose controls

1. Add a delegate protocol near the top of the file:
```swift
@MainActor protocol DetailViewControllerDelegate: AnyObject {
	func detailViewController(_: DetailViewController, didRequestInAppBrowserFor url: URL)
	func detailViewControllerDidRequestArticle(_: DetailViewController)
}
```
2. Add `weak var delegate: DetailViewControllerDelegate?` to `DetailViewController`.
3. Change the two "open"/"return" entry points so they ASK the delegate instead of swapping directly:
   - In `openInAppBrowser(_:url:)` (the `DetailWebViewControllerDelegate` method, from link clicks): replace its body with
     ```swift
     guard detailWebViewController === currentWebViewController else { return }
     delegate?.detailViewController(self, didRequestInAppBrowserFor: url)
     ```
   - In the swipe handler from Task 3: for `.openWeb` call `delegate?.detailViewController(self, didRequestInAppBrowserFor: url)`; for `.returnToArticle` call `delegate?.detailViewControllerDidRequestArticle(self)`.
   - In `detailBrowserViewControllerDidRequestArticle(_:)` (Esc from the browser): call `delegate?.detailViewControllerDidRequestArticle(self)`.
4. Rename the actual swap methods to be driven by the coordinator, and expose browser controls:
```swift
	func showBrowser(url: URL) {
		statusBarView.mouseoverLink = nil
		let controller = DetailBrowserViewController()
		controller.delegate = self
		browserViewController = controller
		containerView.contentView = controller.view   // realize the view before load
		controller.load(url)
		controller.focusWebView()
		isShowingBrowser = true
	}

	func dismissBrowser() {
		guard isShowingBrowser else { return }
		isShowingBrowser = false
		browserViewController?.stopMediaPlayback()
		browserViewController = nil
		containerView.contentView = currentWebViewController.view
		focus()
	}

	var isBrowsing: Bool { isShowingBrowser }
	var browserCanGoBack: Bool { browserViewController?.canGoBack ?? false }
	var browserCanGoForward: Bool { browserViewController?.canGoForward ?? false }
	func browserGoBack() { browserViewController?.goBack() }
	func browserGoForward() { browserViewController?.goForward() }
	func browserReload() { browserViewController?.reload() }
	func browserOpenInDefaultBrowser() { browserViewController?.openInDefaultBrowser() }
```
5. Keep `dismissBrowserIfNeeded()` but make it delegate-aware: the existing calls at the start of `setState`, `showDetail`, and `createNewWebViewsAndRestoreState` must still tear the browser down on context change. Make `dismissBrowserIfNeeded()` notify the coordinator so the chrome is also restored:
```swift
	func dismissBrowserIfNeeded() {
		guard isShowingBrowser else { return }
		delegate?.detailViewControllerDidRequestArticle(self)
	}
```
   …and have the coordinator's "return to article" path call `dismissBrowser()` (which actually swaps the view). This keeps a single restore path. (If `delegate` is nil, fall back to calling `dismissBrowser()` directly so the detail pane is still correct.)

> Net: `DetailViewController` no longer decides chrome; it asks the coordinator, which collapses/expands the sidebar and swaps the toolbar, then calls back `showBrowser`/`dismissBrowser`.

### 4B — `MainWindowController`: browser toolbar, sidebar, actions

1. Add toolbar identifiers to the `extension NSToolbarItem.Identifier` block (around line 785):
```swift
	static let browserGoArticle = NSToolbarItem.Identifier("browserGoArticle")
	static let browserGoBack = NSToolbarItem.Identifier("browserGoBack")
	static let browserGoForward = NSToolbarItem.Identifier("browserGoForward")
	static let browserReload = NSToolbarItem.Identifier("browserReload")
	static let browserOpenInSafari = NSToolbarItem.Identifier("browserOpenInSafari")
```
2. Store toolbars and sidebar state (near other stored properties):
```swift
	private var mainToolbar: NSToolbar?
	private var browserToolbar: NSToolbar?
	private var wasSidebarCollapsed = false
```
   In `windowDidLoad()`, after the existing toolbar is created and assigned, capture it: `mainToolbar = window?.toolbar`.
3. Set `detailViewController?.delegate = self` where the other child controllers are wired (where `detailViewController` is obtained from the split items, ~line 49/101).
4. Build the browser toolbar lazily and a separate delegate path. Add a dedicated delegate object OR reuse `self` and branch on `toolbar.identifier`. Simplest: a small private `NSObject` delegate class is overkill — instead branch in the existing delegate methods on `toolbar.identifier == "MainWindowBrowserToolbar"`. Implement:
```swift
	private func makeBrowserToolbar() -> NSToolbar {
		let toolbar = NSToolbar(identifier: "MainWindowBrowserToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = false
		toolbar.autosavesConfiguration = false
		return toolbar
	}
```
   In `toolbar(_:itemForItemIdentifier:...)`, add cases for the five browser identifiers, e.g.:
```swift
		case .browserGoArticle:
			let title = NSLocalizedString("Article", comment: "Return to article")
			return buildToolbarButton(.browserGoArticle, title, NSImage(systemSymbolName: "chevron.left", accessibilityDescription: title)!, "browserGoArticle:")
		case .browserGoBack:
			let title = NSLocalizedString("Back", comment: "Back")
			return buildToolbarButton(.browserGoBack, title, NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: title)!, "browserGoBack:")
		case .browserGoForward:
			let title = NSLocalizedString("Forward", comment: "Forward")
			return buildToolbarButton(.browserGoForward, title, NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: title)!, "browserGoForward:")
		case .browserReload:
			let title = NSLocalizedString("Reload", comment: "Reload")
			return buildToolbarButton(.browserReload, title, NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: title)!, "browserReload:")
		case .browserOpenInSafari:
			let title = NSLocalizedString("Open in Browser", comment: "Open in Browser")
			return buildToolbarButton(.browserOpenInSafari, title, Assets.Images.openInBrowser, "browserOpenInSafari:")
```
   (Confirm `buildToolbarButton`'s signature by reading its definition; match the image parameter type — the article items pass `Assets.Images.*` (an `NSImage`). Use `NSImage(systemSymbolName:...)!` for the SF Symbol ones, or add matching assets if `buildToolbarButton` requires a specific type.)
   Provide identifier lists when the browser toolbar asks:
```swift
	// inside toolbarAllowedItemIdentifiers / toolbarDefaultItemIdentifiers, branch:
	if toolbar.identifier == "MainWindowBrowserToolbar" {
		return [.toggleSidebar, .browserGoArticle, .flexibleSpace, .browserGoBack, .browserGoForward, .browserReload, .flexibleSpace, .browserOpenInSafari]
	}
```
   (Return that array for both allowed and default when it's the browser toolbar; keep the existing arrays for the main toolbar.)
5. Toolbar action methods + validation:
```swift
	@objc func browserGoArticle(_ sender: Any?) { closeInAppBrowser() }
	@objc func browserGoBack(_ sender: Any?) { detailViewController?.browserGoBack() }
	@objc func browserGoForward(_ sender: Any?) { detailViewController?.browserGoForward() }
	@objc func browserReload(_ sender: Any?) { detailViewController?.browserReload() }
	@objc func browserOpenInSafari(_ sender: Any?) { detailViewController?.browserOpenInDefaultBrowser() }
```
   In `validateUserInterfaceItem(_:)`, add cases: `browserGoBack` → `detailViewController?.browserCanGoBack ?? false`; `browserGoForward` → `detailViewController?.browserCanGoForward ?? false`; the others → `true`.
   Observe nav-state changes to revalidate: in `windowDidLoad()` add
```swift
		NotificationCenter.default.addObserver(self, selector: #selector(browserNavigationStateDidChange(_:)), name: .DetailBrowserNavigationStateDidChange, object: nil)
```
   and
```swift
	@objc func browserNavigationStateDidChange(_ note: Notification) {
		makeToolbarValidate()
	}
```
6. The coordinator entry/exit + `DetailViewControllerDelegate` conformance:
```swift
extension MainWindowController: DetailViewControllerDelegate {

	func detailViewController(_ controller: DetailViewController, didRequestInAppBrowserFor url: URL) {
		showInAppBrowser(url: url)
	}

	func detailViewControllerDidRequestArticle(_ controller: DetailViewController) {
		closeInAppBrowser()
	}
}

private extension MainWindowController {

	func showInAppBrowser(url: URL) {
		guard !(detailViewController?.isBrowsing ?? false) else {
			detailViewController?.showBrowser(url: url)   // already browsing: just load
			return
		}
		wasSidebarCollapsed = sidebarSplitViewItem?.isCollapsed ?? false
		sidebarSplitViewItem?.animator().isCollapsed = true

		if browserToolbar == nil { browserToolbar = makeBrowserToolbar() }
		window?.toolbar = browserToolbar

		detailViewController?.showBrowser(url: url)
	}

	func closeInAppBrowser() {
		guard detailViewController?.isBrowsing ?? false else { return }
		detailViewController?.dismissBrowser()
		window?.toolbar = mainToolbar
		sidebarSplitViewItem?.animator().isCollapsed = wasSidebarCollapsed
		makeToolbarValidate()
	}
}
```
   (`sidebarSplitViewItem` accessor already exists ~line 984. Confirm its exact name and the `detailViewController` accessor name by reading the file; adapt.)

**Step 1–N:** Make the 4A edits, then the 4B edits. Read each method before editing. Build after each sub-section if helpful, but the commit happens once at the end.

**Build:** expect `** BUILD SUCCEEDED **`. Resolve compile errors in these two files only; if a fix requires changing specified behavior, STOP and ask. **Run unit tests:** expect pass.

**Commit (one commit):**
```bash
git add Mac/MainWindow/Detail/DetailViewController.swift Mac/MainWindow/MainWindowController.swift
git commit -m "Swap to browser toolbar and collapse the sidebar while browsing"
```

---

## Task 5: Manual verification + final review

Build and run the Mac app (do NOT add an iCloud account in this unsigned build — it crashes; use On My Mac). Verify:

1. Click an in-content link → sidebar collapses, toolbar shows browser controls (‹ Article, back, forward, reload, Open in Browser), URL appears bottom-right.
2. Navigate within the page → back/forward enable/disable correctly.
3. ‹ Article and Esc → restore toolbar, restore sidebar to its prior state, return to the article at its scroll position.
4. The sidebar restore respects prior state: collapse the sidebar yourself first, then open/close the webview — it should stay collapsed on close.
5. Reader swipe: right-to-left on an article opens its link in the webview; left-to-right while browsing returns to the article.
6. Selecting a different article while browsing dismisses the panel and restores chrome.
7. ⌘/shift-click a link and mailto: links still go to the external browser.
8. URL overlay truncates long URLs and sits bottom-right.

Document results. Then dispatch a final whole-branch code review and finish the branch.

---

## Notes for the implementer
- Files are target members by folder — no `project.pbxproj` edits.
- Read `buildToolbarButton`'s definition in `MainWindowController.swift` before using it; match its image parameter type (the existing calls pass `Assets.Images.*`). If it can't take an `NSImage` directly for the SF Symbol items, either add image assets or construct `RSToolbarItem`/`NSToolbarItem` manually like the `.readerView` case does.
- `swipe(with:)` honors the trackpad "swipe between pages" setting. If it doesn't fire in manual testing, the fallback (out of scope for the plan unless needed) is `scrollWheel(with:)` + `NSEvent.trackSwipeEvent`. Flag it rather than guessing.
- Keep the single restore path: every "return to article" (Esc, ‹ Article, swipe, context change) funnels through `closeInAppBrowser()` → `dismissBrowser()`.
