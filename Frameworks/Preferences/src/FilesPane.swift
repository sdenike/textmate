// Frameworks/Preferences/src/FilesPane.swift
import SwiftUI

// The two scope selectors kSettingsFileTypeKey is edited under. One key, two
// values: "which grammar does a brand new document get" and "which grammar
// does a file whose type we could not work out get". Literals rather than
// bridge functions because they are plain strings in the AppKit pane too --
// they are not std::string constants from settings/keys.h.
private let kUntitledScope    = "attr.untitled"
private let kUnknownTypeScope = "attr.file.unknown-type"

// MARK: - Encoding control

// OakEncodingPopUpButton, hosted rather than rebuilt -- see the shim's comment
// in Preferences-Bridging-Header.h for why the control survives the port and
// why Swift reaches it through three functions instead of the class.
private struct EncodingPopUpButton: NSViewRepresentable {
	@Binding var encoding: String

	// The control has no target/action to hang a callback on: its menu items
	// target the button itself, and -setEncoding: is what the AppKit pane
	// observed, through a Cocoa binding. KVO is the same mechanism that
	// binding used, minus the binding.
	// @unchecked Sendable so observeValue may hand self to assumeIsolated: the
	// checker cannot see that this object never leaves the main thread, and
	// every path to it is main-actor -- makeCoordinator and updateNSView are
	// @MainActor by NSViewRepresentable, and KVO delivers on the thread that
	// assigned, which for -setEncoding: is a menu selection. NSObject cannot
	// carry @MainActor here instead: observeValue overrides a nonisolated
	// superclass method.
	final class Coordinator: NSObject, @unchecked Sendable {
		var onChange: (String) -> Void = { _ in }

		override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
			guard let button = object as? NSPopUpButton else { return }
			// KVO fires synchronously on whichever thread assigned, and
			// -setEncoding: only ever runs from a menu selection, i.e. the
			// main thread. assumeIsolated states that rather than hiding it
			// behind a hop, which would land after SwiftUI's update pass.
			MainActor.assumeIsolated {
				onChange(TMEncodingPopUpButtonGetEncoding(button) ?? "")
			}
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> NSPopUpButton {
		let button = TMCreateEncodingPopUpButton()
		applyEncoding(to: button)
		button.addObserver(context.coordinator, forKeyPath: "encoding", options: [], context: nil)
		return button
	}

	func updateNSView(_ button: NSPopUpButton, context: Context) {
		context.coordinator.onChange = { encoding = $0 }
		applyEncoding(to: button)
	}

	static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
		button.removeObserver(coordinator, forKeyPath: "encoding")
	}

	// An empty value means the setting was never written; the control already
	// defaults itself to UTF-8, so leave it alone rather than clearing its
	// menu selection.
	private func applyEncoding(to button: NSPopUpButton) {
		if !encoding.isEmpty {
			TMEncodingPopUpButtonSetEncoding(button, encoding)
		}
	}
}

// MARK: - Files pane

struct FilesPaneView: View {
	// Three negated checkboxes: every label is phrased positively against a
	// key named disable…, so getting one backwards silently inverts a user's
	// setting while the pane still looks right.
	@AppStorage(kUserDefaultsDisableSessionRestoreKey)            private var disableSessionRestore = false
	@AppStorage(kUserDefaultsDisableNewDocumentAtStartupKey)      private var disableNewDocumentAtStartup = false
	@AppStorage(kUserDefaultsDisableNewDocumentAtReactivationKey) private var disableNewDocumentAtReactivation = false

	// settings_t-backed, seeded once and written back on SELECTION, never
	// continuously: settings_t::set is two read_file parses plus a non-atomic
	// truncate-and-rewrite of the user's Global.tmProperties, so every write
	// is a window in which a crash empties that file. A Picker's setter fires
	// once per choice, which is what makes writing from it safe -- unlike the
	// Projects pane's text fields, which had to defer to a commit.
	@State private var newFileType     = TMSettingsGetScopedString(TMSettingsFileTypeKey(), kUntitledScope)
	@State private var unknownFileType = TMSettingsGetScopedString(TMSettingsFileTypeKey(), kUnknownTypeScope)
	@State private var encoding        = TMSettingsGetString(TMSettingsEncodingKey())
	@State private var lineEndingsTag  = Int(TMLineEndingsTagForValue(TMSettingsGetString(TMSettingsLineEndingsKey())))

	// Marshalled by FilesPreferences -loadView from bundles::query, already
	// filtered and ordered by TMFileTypeItemsSorted. Passed at construction,
	// not pushed in like the Projects pane's locations: the installed grammars
	// do not change while the pane is open, and the factory measures
	// fittingSize off a view that must already know its menu contents.
	let fileTypes: [TMFileTypeItem]

	var body: some View {
		SettingsPane {
			Section("At startup:") {
				Toggle(isOn: openLastSessionBinding) {
					Text("Open documents from last session")
					// A second Text in a Toggle's label is AppKit's small
					// secondary line -- the AppKit pane spent a whole extra
					// grid row plus a custom placement constraint on this.
					Text("Hold shift (⇧) to bypass")
				}
			}

			Section("With no open documents:") {
				Toggle("Create one at startup", isOn: createAtStartupBinding)
				Toggle("Create one when re-activated", isOn: createOnActivationBinding)
			}

			Section {
				Picker("New document type:", selection: fileTypeBinding(for: kUntitledScope)) {
					ForEach(fileTypes, id: \.self) { item in
						Text(item.name).tag(item.scope ?? "")
					}
				}

				Picker("Unknown document type:", selection: fileTypeBinding(for: kUnknownTypeScope)) {
					// Heads the menu with a nil-equivalent: choosing it stores
					// NULL_STR, exactly as the AppKit menu item with a nil
					// representedObject did, and it is what an unmatched
					// stored value falls back to displaying.
					Text("Prompt for type").tag("")
					Divider()
					ForEach(fileTypes, id: \.self) { item in
						Text(item.name).tag(item.scope ?? "")
					}
				}

				LabeledContent("Encoding:") {
					// Without .fixedSize(), NSViewRepresentable fills the width
					// LabeledContent offers instead of hugging the button's own
					// intrinsic size (measured 206pt) -- unlike a native Picker,
					// whose control already sizes to its content. That left the
					// button 237pt wide with its title stuck to the left edge and
					// a visible gap before the chevron, while the other three
					// rows' values sit flush against theirs. Confirmed by an
					// offscreen render: with this, the button's box shrinks to its
					// content width and its trailing edge lines up with the other
					// three rows' at x=460; fittingSize is unchanged.
					EncodingPopUpButton(encoding: encodingBinding)
						.fixedSize()
				}

				Picker("Line endings:", selection: lineEndingsBinding) {
					Text("LF (recommended)").tag(0)
					Text("CR (Mac Classic)").tag(1)
					Text("CRLF (Windows)").tag(2)
				}
			}
		}
	}

	private var openLastSessionBinding: Binding<Bool> {
		Binding(get: { !disableSessionRestore }, set: { disableSessionRestore = !$0 })
	}

	private var createAtStartupBinding: Binding<Bool> {
		Binding(get: { !disableNewDocumentAtStartup }, set: { disableNewDocumentAtStartup = !$0 })
	}

	private var createOnActivationBinding: Binding<Bool> {
		Binding(get: { !disableNewDocumentAtReactivation }, set: { disableNewDocumentAtReactivation = !$0 })
	}

	private var encodingBinding: Binding<String> {
		Binding(get: { encoding }, set: { newValue in
			encoding = newValue
			TMSettingsSetString(TMSettingsEncodingKey(), newValue)
		})
	}

	private var lineEndingsBinding: Binding<Int> {
		Binding(get: { lineEndingsTag }, set: { newTag in
			lineEndingsTag = newTag
			TMSettingsSetString(TMSettingsLineEndingsKey(), TMLineEndingsValueForTag(NSInteger(newTag)))
		})
	}

	private func fileTypeBinding(for scope: String) -> Binding<String> {
		Binding(get: { displayedFileType(for: scope) }, set: { newValue in
			if scope == kUntitledScope {
				newFileType = newValue
			} else {
				unknownFileType = newValue
			}
			// "" is the "Prompt for type" row, and nil is how that reaches
			// settings_t as NULL_STR rather than as an empty grammar name.
			TMSettingsSetScopedString(TMSettingsFileTypeKey(), newValue.isEmpty ? nil : newValue, scope)
		})
	}

	// A stored grammar that is not installed selects nothing in AppKit, which
	// leaves the popup showing its first item. SwiftUI shows a blank instead,
	// so fall back explicitly -- for display only, since writing here would
	// rewrite Global.tmProperties merely because the pane was opened.
	private func displayedFileType(for scope: String) -> String {
		let stored = scope == kUntitledScope ? newFileType : unknownFileType
		if fileTypes.contains(where: { $0.scope == stored }) {
			return stored
		}
		return scope == kUntitledScope ? (fileTypes.first?.scope ?? "") : ""
	}
}

extension SettingsPaneFactory {
	@MainActor
	@objc public static func filesView(fileTypes: [TMFileTypeItem]) -> NSView {
		let view = NSHostingView(rootView: FilesPaneView(fileTypes: fileTypes))
		// Same fittingSize discipline as the other panes: the pane is pinned
		// to this (OakTransitionViewController.mm:42), and a hosted AppKit
		// control is exactly the kind of subview that can contribute nothing
		// in one direction -- as Table did for the Variables pane.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
