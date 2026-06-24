# Offline Reader View with Mozilla Readability

Date: 2026-06-24

## Goal

Replace NetNewsWire's Reader View engine (the hosted Feedbin/Mercury parser,
which needs private API keys absent from source builds) with Mozilla's
`Readability.js` running locally. Reader View then works in any build — no API
keys, no third-party parser service.

"Offline" here means no external parser and no keys; the article page itself is
still downloaded (any reader view must fetch the page). Extraction runs locally.

## Background (verified in code)

- `Shared/Article Extractor/ArticleExtractor.swift` currently builds
  `https://extract.feedbin.com/parser/<mercuryClientID>/<hmac>` and decodes the
  JSON into `ExtractedArticle`. With empty `SecretKey.mercuryClientID` /
  `feedlyClientSecret` (the source-build default) the request 404s and Reader
  View silently fails.
- The extractor is in `Shared/`, used by both Mac and iOS. Public surface:
  `init?(_ articleLink:delegate:)`, `process()`, `cancel()`, `state`,
  `ArticleExtractorState`, and the `ArticleExtractorDelegate` callbacks
  `articleExtractionDidComplete(extractedArticle:)` /
  `articleExtractionDidFail(with:)`.
- `ExtractedArticle` (Codable) has many fields, but `ArticleRenderer` only reads
  `.content` (the cleaned HTML) and `.url` (used as base URL). Everything else
  is cosmetic.

## Decisions

- **Scope:** shared — replace the engine in `ArticleExtractor` so both Mac and
  iOS get offline Reader View.
- **Strategy:** replace entirely. Drop the Feedbin/Mercury call and the
  `SecretKey` dependency for extraction. No fallback.

## Approach

Run `Readability.js` inside an offscreen `WKWebView` (JavaScriptCore has no DOM;
`WKWebView` exists on both platforms). Letting `WKWebView` load the URL yields a
fully built DOM with correct base-URL resolution.

Data flow (the public surface is unchanged, so callers are untouched):
1. Reader View toggled → `ArticleExtractor(articleLink)` created (as today).
2. `process()` sets `state = .processing` and loads the article URL into a
   hidden, offscreen `WKWebView`.
3. On `WKNavigationDelegate.didFinish`, inject `Readability.js` and evaluate a
   wrapper: `try { return JSON.stringify(new Readability(document.cloneNode(true)).parse()) } catch { return null }`.
   (`cloneNode(true)` because Readability mutates the DOM.)
4. Parse the JSON and map to `ExtractedArticle` (see mapping). Empty/`null`
   `content` → `.failedToParse`.
5. Call `articleExtractionDidComplete(extractedArticle:)` — downstream rendering
   is identical.

### Readability → ExtractedArticle mapping

| Readability field | ExtractedArticle |
|---|---|
| `content` (HTML) | `content` |
| `title` | `title` |
| `byline` | `author` |
| `excerpt` | `excerpt` and `dek` |
| `siteName` | `domain` |
| `dir` | `direction` |
| word count of `textContent` | `wordCount` |
| (article URL) | `url` |
| — | `datePublished`, `leadImageURL`, `nextPageURL`, `totalPages`, `renderedPages` = nil |

The mapping is a pure function over the decoded Readability result and the
source URL — unit-tested.

## Components

- **`ArticleExtractor` rewrite** (`Shared/Article Extractor/`): owns an
  offscreen `WKWebView` (private config, a `WKUserScript` injecting
  `Readability.js` at document-end). Implements `WKNavigationDelegate`. Keeps
  `init?`, `process()`, `cancel()`, `state`, and the delegate contract
  identical.
- **`Readability.js`** vendored into the app bundle, added to both app targets'
  resources, with Mozilla's Apache-2.0 license/attribution retained.
- **`ReadabilityResult`** Codable struct matching the parse JSON, plus the pure
  mapping to `ExtractedArticle`.

## Error handling

- `didFail` / `didFailProvisionalNavigation` → `.failedToParse` (ignore
  `NSURLErrorCancelled`).
- Readability returns `null` or empty `content` → `.failedToParse`.
- Watchdog timeout (~30s) → `.failedToParse`, so a hung page resolves.
- `cancel()` stops the load and detaches the message handler / nav delegate to
  avoid leaks.
- On any failure the existing UI path keeps the original article — no crash,
  same degradation as today.

## Testing

- Unit: the pure `ReadabilityResult → ExtractedArticle` mapping (content,
  byline→author, excerpt→dek, siteName→domain, dir, word count, nils).
- Manual: toggle Reader View in the from-source build (7.1b6) on a feed that
  shows only a summary → full article text appears, with no parser keys.
  Confirm a parse failure leaves the original article intact.

## Out of scope (YAGNI)

- Pagination (`next_page_url`, multi-page articles).
- Lead-image / publish-date extraction beyond what Readability returns.
- Caching extracted results across launches.
- Changing the rendering or theming.
