// Applications/TextMate/src/AboutWindow/AboutView.swift
//
// The About window's content view: three SwiftUI pages (About, Changes,
// Legal) hosted inside AboutWindowController.mm's existing NSPanel/toolbar/
// segmented-control shell, which stays Objective-C++ unchanged. This
// replaces the WKWebView, its WKUserScript version/copyright injection, and
// the "textmate" script-message bridge entirely -- there is no JavaScript
// left in the About window.

import SwiftUI

enum AboutPage: String {
	case about   = "About"
	case changes = "Changes"
	case legal   = "Legal"
}

// AppKit always drives which page is showing (the segmented control, or
// -showChangesWindow: after an update) -- nothing in these views ever
// changes the page itself -- so this only needs to flow one way, in.
@MainActor
final class AboutViewModel: ObservableObject {
	@Published var page: AboutPage = .about
}

struct AboutRootView: View {
	@ObservedObject var model: AboutViewModel

	var body: some View {
		Group {
			switch model.page {
				case .about:   AboutPageView()
				case .changes: ChangesPageView()
				case .legal:   LegalPageView()
			}
		}
		.frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
	}
}

// Renders a bullet's, a paragraph block's, or a section's worth of content:
// each segment is either a markdown paragraph (inline formatting only --
// bold, italic, code spans, links -- via AttributedString(markdown:)) or a
// fenced code block, kept verbatim and set in a monospaced block instead of
// being handed to the markdown parser. .inlineOnlyPreservingWhitespace is
// load-bearing, not the default: gen_about_data already rejoins hard-wrapped
// source lines into one line per paragraph and separates paragraphs with a
// blank line, and this must preserve that whitespace exactly rather than
// reflow it again or collapse it away (verified against the real API: every
// inline parsing mode leaves "\n" alone, none of them rewrap).
struct SegmentsView: View {
	let segments: [ContentSegment]

	private static let markdownOptions = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)

	private static func attributed(_ value: String) -> AttributedString {
		(try? AttributedString(markdown: value, options: markdownOptions)) ?? AttributedString(value)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
				if segment.kind == "code" {
					Text(segment.value)
						.font(.system(.body, design: .monospaced))
						.textSelection(.enabled)
						.padding(8)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(Color.gray.opacity(0.15))
						.clipShape(RoundedRectangle(cornerRadius: 6))
				} else {
					Text(Self.attributed(segment.value))
						.textSelection(.enabled)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
		}
	}
}

struct AboutPageView: View {
	private var version: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
	}

	private var copyright: String {
		Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				Text("TextMate version \(version)").font(.title2.bold())

				Text("The manual is a work in progress and can be found at [macromates.com/textmate/manual](https://macromates.com/textmate/manual/). The MacroMates Blog has a [TextMate 2 category](https://blog.macromates.com/categories/textmate-2/).")

				Text("There is a [FAQ](https://github.com/textmate/textmate/wiki/FAQ) and [hidden settings](https://github.com/textmate/textmate/wiki/Hidden-Settings) page.")

				Text("For comments, questions, and general feedback see [github.com/sdenike/textmate/issues](https://github.com/sdenike/textmate/issues).")

				Text("TextMate is the work of many hands. Thank you to everyone listed among the [contributors](https://github.com/sdenike/textmate/graphs/contributors) and in the [commit history](https://github.com/sdenike/textmate/commits/master).")

				Text("TextMate is a trademark of Allan Odgaard and the program is \(copyright).")
					.font(.callout)
					.foregroundStyle(.secondary)
					.italic()
			}
			.textSelection(.enabled)
			.padding(20)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

struct LegalPageView: View {
	@State private var document = AboutData.loadLegal()

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				if let document {
					if let intro = document.intro {
						SegmentsView(segments: intro)
					}
					ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
						VStack(alignment: .leading, spacing: 8) {
							if let category = section.category {
								Text(category).font(.title3.bold())
							}
							if let intro = section.intro {
								SegmentsView(segments: intro)
							}
						}
					}
				} else {
					Text("Unable to load licence information.").foregroundStyle(.secondary)
				}
			}
			.padding(20)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}

struct ReleaseHeaderView: View {
	let release: ChangelogRelease

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			if let date = release.date {
				Text(date).font(.headline)
				if let version = release.version {
					Text(version)
						.font(.system(.subheadline, design: .monospaced))
						.foregroundStyle(.secondary)
				}
			} else {
				Text(release.title).font(.headline)
			}
		}
	}
}

struct ChangelogSectionView: View {
	let section: ContentSection

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			if let category = section.category {
				Text(category).font(.subheadline.bold()).foregroundStyle(.secondary)
			}
			if let intro = section.intro {
				SegmentsView(segments: intro)
			}
			ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
				HStack(alignment: .top, spacing: 6) {
					Text("•")
					SegmentsView(segments: item)
				}
			}
		}
	}
}

struct ReleaseView: View {
	let release: ChangelogRelease

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			ReleaseHeaderView(release: release)
			if let intro = release.intro {
				SegmentsView(segments: intro)
			}
			ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
				ChangelogSectionView(section: section)
			}
		}
	}
}

struct ChangesPageView: View {
	@State private var document = AboutData.loadChangelog()

	var body: some View {
		Group {
			if let document {
				ScrollView {
					// LazyVStack so 202 releases -- most of them off-screen at any
					// time -- cost nothing to lay out or render until scrolled into
					// view.
					LazyVStack(alignment: .leading, spacing: 20) {
						ForEach(document.releases) { release in
							ReleaseView(release: release)
							Divider()
						}
					}
					.padding(20)
				}
			} else {
				Text("Unable to load release notes.").foregroundStyle(.secondary).padding(20)
			}
		}
	}
}

// The Objective-C++ entry point. `public` is load-bearing (see the Swift
// section of CLAUDE.md): an internal @objc declaration compiles and reaches
// the .swiftmodule but is silently absent from the generated
// TextMate-Swift.h. Long-lived, unlike SetupAssistantHostingController's
// per-run factory: AboutWindowController's window is a process-lifetime
// singleton whose toolbar keeps switching pages on an already-visible
// window, rather than being built once and torn down.
@objc(AboutHostingController)
@MainActor
public final class AboutHostingController: NSObject {
	private let model = AboutViewModel()

	@objc public lazy var view: NSView = NSHostingView(rootView: AboutRootView(model: model))

	@objc public func showPage(_ pageName: String) {
		model.page = AboutPage(rawValue: pageName) ?? .about
	}
}
