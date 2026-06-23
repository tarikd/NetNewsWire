# In-app web view panel for the Mac detail pane

Date: 2026-06-24

## Goal

Clicking a link inside an article on macOS should load the page in an in-app
web view that replaces the article detail pane, instead of opening Safari. The
panel is a small browser with its own controls, and a one-tap way back to the
article.

## Background

The Mac detail pane renders article HTML in a single `DetailWebView`
(`Mac/MainWindow/Detail/`). `DetailViewController` swaps the container's
`contentView` between a regular article web view controller and a search
variant. Every in-content link click funnels through one bottleneck:

- `DetailWebViewController.webView(_:decidePolicyFor:)` catches
  `.linkActivated`, cancels the navigation, and calls `openInBrowser(_:flags:)`
  → `Browser.open(...)`, which sends the URL to the default browser.
- The `window.open` case (`webView(_:createWebViewWith:...)`) routes the same
  way.

That single decision point is where we intervene.

## Behavior

- A normal click on an in-content link loads the page in the panel.
- Shift/⌘-click is preserved as the click-time "force Safari" escape hatch
  (the existing invert-preference gesture).
- Non-`http(s)` links (mailto:, custom schemes) are never loaded in the panel —
  they go straight to `Browser.open` so the OS routes them.

## Approach

Chosen: a **separate browser content view** rather than reusing the article web
view.

Reusing the article web view (flip `.cancel` to `.allow`) is a smaller diff but
tangles the web view's back/forward history with the `loadHTMLString` article
render and the hidden blank page, and forces re-fetching the article scroll
position. Fragile.

A separate browser view mirrors how the detail pane already swaps `contentView`,
leaves the article web view (and its scroll position) untouched, and gives the
panel a clean, isolated navigation history.

## Components

### 1. `DetailBrowserViewController` (new, `Mac/MainWindow/Detail/`)

- Owns a plain `WKWebView` (clean configuration — no article icon scheme
  handlers) and a programmatic toolbar built with `NSStackView`, so no xib
  changes are needed.
- Toolbar, left to right:
  - **‹ Article** — dismiss the panel, return to the article.
  - **back** / **forward** — web history; enabled via KVO on the web view's
    `canGoBack` / `canGoForward`.
  - **reload**.
  - **address field** — read-only `NSTextField` showing the current URL.
  - **Open in Safari** — hands `webView.url` to `Browser.open`.
- Updates the address field and button states from `WKNavigationDelegate`
  callbacks (`didCommit` / `didFinish`).
- Links *inside* the loaded page navigate normally and stay in the panel.
- On `didFail` / `didFailProvisionalNavigation`, show a minimal error state with
  the URL still visible, so a dead link doesn't trap the user on a blank page.

### 2. Delegate hook in `DetailWebViewController`

- Add `func openInAppBrowser(_ url: URL)` to
  `DetailWebViewControllerDelegate`.
- In `decidePolicyFor`, for `.linkActivated`: extract a small pure decision
  `(url, modifierFlags) → .inApp | .safari`. If `.safari` (modifier forces it,
  or non-http(s) scheme), call the existing `openInBrowser`; otherwise call
  `delegate?.openInAppBrowser(url)`. Apply the same redirect to the
  `createWebViewWith` (`window.open`) path.

### 3. `DetailViewController` orchestration

- Lazily create one shared `DetailBrowserViewController`.
- `openInAppBrowser(url:)` → load the URL and swap
  `containerView.contentView` to the browser view.
- "‹ Article" / Esc → swap `contentView` back to
  `currentWebViewController.view`.
- Browser visibility is a single piece of state. Selecting a different article
  (`setState`), switching source mode (regular ↔ search), or the
  JS-preference web view rebuild all dismiss the browser first, so the user
  never returns from the panel to a stale article.
- Dismissing stops the browser web view's media playback to avoid background
  audio.

## Testing

- **Unit:** the routing decision `(url, modifierFlags) → .inApp | .safari` is a
  pure function — test http→in-app, ⌘-click→Safari, mailto→Safari.
- **Manual:** build the Mac app and verify: in-content link loads in the panel;
  links within the page drive web back/forward; reload works; Open in Safari
  hands off; ‹ Article restores the article with its scroll position; selecting
  another article mid-browse auto-dismisses the panel.

## Out of scope (YAGNI)

- Touching the "Open in Browser" command that opens the *article's* own URL
  externally — this feature targets in-content link clicks only.
- A 4th column, tabs, or a separate browser window.
- iOS — Mac only.
