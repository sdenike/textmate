// Frameworks/Preferences/src/SettingsFormStyle.swift
import SwiftUI

// Every Settings pane wraps its content in this rather than using Form directly,
// so "uniform and modern" is decided once. A pane declares WHAT it configures;
// none of them decides how it looks. Six panes each making their own layout
// choices is exactly how a window ends up looking inconsistent.
public struct SettingsPane<Content: View>: View {
	private let content: Content

	public init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	public var body: some View {
		Form {
			content
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
	}
}
