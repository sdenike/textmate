// Applications/TextMate/src/AboutWindow/AboutData.swift
//
// Decodes the two plists bin/gen_about_data builds from CHANGELOG.md and
// about/Legal.md (see that script's own header comment for the parse). Pure
// Swift/Foundation -- no Objective-C type crosses the bridge for the About
// window, so nothing here is declared in TextMate-Bridging-Header.h.

import Foundation

// One paragraph's worth of markdown text, or one fenced code block, kept
// verbatim. `kind` mirrors gen_about_data's own "text"/"code" tags rather
// than being a Swift enum, so an unrecognised future tag decodes instead of
// throwing away the whole document.
struct ContentSegment: Decodable {
	let kind: String
	let value: String
}

// A `## Category` under a release, or a `## Heading` in Legal.md. `items` is
// always present (possibly empty) because both call sites of
// parse_document_body build it unconditionally; `category`/`intro` are
// omitted by the generator when absent, hence Optional here.
struct ContentSection: Decodable {
	let category: String?
	let intro: [ContentSegment]?
	let items: [[ContentSegment]]
}

struct ChangelogRelease: Decodable, Identifiable {
	let title: String
	let date: String?
	let version: String?
	let intro: [ContentSegment]?
	let sections: [ContentSection]
	var id: String { title }
}

struct ChangelogDocument: Decodable {
	let releases: [ChangelogRelease]
}

struct LegalDocument: Decodable {
	let intro: [ContentSegment]?
	let sections: [ContentSection]
}

enum AboutData {
	static func loadChangelog() -> ChangelogDocument? {
		load("Changelog")
	}

	static func loadLegal() -> LegalDocument? {
		load("Legal")
	}

	private static func load<T: Decodable>(_ name: String) -> T? {
		guard let url = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: "About"),
		      let data = try? Data(contentsOf: url) else { return nil }
		return try? PropertyListDecoder().decode(T.self, from: data)
	}
}
