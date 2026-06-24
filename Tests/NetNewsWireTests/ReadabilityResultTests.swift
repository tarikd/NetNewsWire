import XCTest
@testable import NetNewsWire

final class ReadabilityResultTests: XCTestCase {

	private func decode(_ json: String) throws -> ReadabilityResult {
		try JSONDecoder().decode(ReadabilityResult.self, from: Data(json.utf8))
	}

	func testMapsCoreFields() throws {
		let json = """
		{"title":"Hello","byline":"Jane Doe","content":"<p>Hi</p>","textContent":"Hi there friend","excerpt":"A summary","siteName":"Example","dir":"ltr","lang":"en","length":15}
		"""
		let result = try decode(json)
		let extracted = result.extractedArticle(url: "https://example.com/post")

		XCTAssertEqual(extracted.title, "Hello")
		XCTAssertEqual(extracted.author, "Jane Doe")
		XCTAssertEqual(extracted.content, "<p>Hi</p>")
		XCTAssertEqual(extracted.excerpt, "A summary")
		XCTAssertEqual(extracted.dek, "A summary")
		XCTAssertEqual(extracted.domain, "Example")
		XCTAssertEqual(extracted.direction, "ltr")
		XCTAssertEqual(extracted.url, "https://example.com/post")
		XCTAssertEqual(extracted.wordCount, 3)
	}

	func testMissingOptionalFieldsBecomeNil() throws {
		let json = #"{"content":"<p>x</p>"}"#
		let result = try decode(json)
		let extracted = result.extractedArticle(url: "https://example.com")

		XCTAssertEqual(extracted.content, "<p>x</p>")
		XCTAssertNil(extracted.author)
		XCTAssertNil(extracted.title)
		XCTAssertNil(extracted.leadImageURL)
		XCTAssertNil(extracted.datePublished)
	}

	func testNilContentWhenAbsent() throws {
		let result = try decode("{}")
		XCTAssertNil(result.content)
	}
}
