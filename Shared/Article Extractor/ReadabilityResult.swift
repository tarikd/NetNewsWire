//
//  ReadabilityResult.swift
//  NetNewsWire
//
//  Decoded output of Mozilla Readability's parse(), mapped to ExtractedArticle.
//

import Foundation

struct ReadabilityResult: Codable {
	let title: String?
	let byline: String?
	let content: String?
	let textContent: String?
	let excerpt: String?
	let siteName: String?
	let dir: String?
	let lang: String?
	let length: Int?
}

extension ReadabilityResult {

	func extractedArticle(url: String) -> ExtractedArticle {
		let words = textContent?
			.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
			.count
		return ExtractedArticle(
			title: title,
			author: byline,
			datePublished: nil,
			dek: excerpt,
			leadImageURL: nil,
			content: content,
			nextPageURL: nil,
			url: url,
			domain: siteName,
			excerpt: excerpt,
			wordCount: words,
			direction: dir,
			totalPages: nil,
			renderedPages: nil
		)
	}
}
