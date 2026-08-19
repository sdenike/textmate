// Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift
import SwiftUI

public enum TMSetupAssistantStep: Int, CaseIterable {
	case welcome = 0
	case appearance = 1
	case bundles = 2

	var title: String {
		switch self {
			case .welcome:    return "Welcome to TextMate"
			case .appearance: return "Appearance"
			case .bundles:    return "Bundles"
		}
	}
}

@MainActor
final class SetupAssistantModel: ObservableObject {
	@Published var step: TMSetupAssistantStep = .welcome
	@Published var appearance: String = "auto"
	// One selection per theme slot, both seeded from the host. A single
	// identifier could only ever describe the slot it was read for: picking
	// Dark after opening in light mode then wrote the light theme's UUID into
	// darkModeThemeUUID, and dark mode resolved to a light theme.
	@Published var selectedThemeIdentifiers: [String: String] = [:]
	// Which slot the theme list edits while appearance is "auto". Light and
	// dark each name their own slot, so this is only consulted for automatic.
	@Published var editingSlot: String = "light"
	@Published var checkedBundleIdentifiers: Set<String> = []

	let host: any TMSetupAssistantHost

	private lazy var allThemes: [TMThemeChoice] = host.availableThemes()

	private lazy var allBundles: [TMBundleChoice] = host.availableBundles()
	var bundles: [TMBundleChoice] { allBundles }

	init(host: any TMSetupAssistantHost) {
		self.host = host
		self.appearance = host.currentAppearance() ?? "auto"
		for slot in ["light", "dark"] {
			if let identifier = host.currentThemeIdentifier(forAppearance: slot) {
				self.selectedThemeIdentifiers[slot] = identifier
			}
		}
		self.checkedBundleIdentifiers = Set(allBundles.filter { $0.recommended && !$0.installed }.map { $0.identifier })
	}

	var isFirstStep: Bool { step == .welcome }
	var isLastStep: Bool  { step == .bundles }

	// Which slot the theme list is showing, and the one finish() writes. Light
	// and dark each name a single slot; automatic uses both keys, so there the
	// user picks which one to edit.
	var editingAppearance: String { appearance == "auto" ? editingSlot : appearance }

	// The list's selection always addresses the slot on screen, so switching
	// the appearance picker switches both the selection and the preview to
	// that slot's theme. nil is ignored rather than stored: a List whose
	// contents change under it can report the vanished selection as no
	// selection, which would drop the slot's real theme on the floor.
	var selectedThemeBinding: Binding<String?> {
		Binding(
			get: { self.selectedThemeIdentifiers[self.editingAppearance] },
			set: { identifier in
				guard let identifier else { return }
				self.selectedThemeIdentifiers[self.editingAppearance] = identifier
			}
		)
	}

	func themes(for appearance: String) -> [TMThemeChoice] {
		allThemes.filter { $0.appearance == appearance || $0.appearance == "unspecified" }
	}

	var selectedTheme: TMThemeChoice? {
		allThemes.first { $0.identifier == selectedThemeIdentifiers[editingAppearance] }
	}

	func binding(for bundle: TMBundleChoice) -> Binding<Bool> {
		Binding(
			get: { bundle.installed || self.checkedBundleIdentifiers.contains(bundle.identifier) },
			set: { isOn in
				if isOn { self.checkedBundleIdentifiers.insert(bundle.identifier) }
				else    { self.checkedBundleIdentifiers.remove(bundle.identifier) }
			}
		)
	}

	func back() {
		guard let previous = TMSetupAssistantStep(rawValue: step.rawValue - 1) else { return }
		step = previous
	}

	func advance() {
		guard let next = TMSetupAssistantStep(rawValue: step.rawValue + 1) else { return }
		step = next
	}

	func finish() {
		// Automatic switches between both themes at runtime, so both slots are
		// editable there and both are written; light and dark each name one
		// slot and leave the other alone. A slot the host had no theme for and
		// the user never chose one for stays absent.
		for slot in (appearance == "auto" ? ["light", "dark"] : [editingAppearance]) {
			if let identifier = selectedThemeIdentifiers[slot] {
				host.applyThemeIdentifier(identifier, appearance: slot)
			}
		}
		// The tri-state picker (light/dark/auto) is distinct from
		// editingAppearance above, which is only ever "light" or "dark" and
		// only picks which slot's theme list to show. Only this call can carry
		// "auto" itself through to the "themeAppearance" default, so Automatic
		// has a real effect instead of being indistinguishable from Light.
		host.applyAppearance(appearance == "auto" ? nil : appearance)

		// -availableBundles now hands back every shipped-tier bundle,
		// installed ones included (checked and disabled, so the step is
		// never empty on an established profile) -- this filter is what
		// keeps an installed bundle out of both outgoing lists. Leaking into
		// `install` would re-download something already present; leaking
		// into `never` would suppress a bundle the user already has, which
		// DocumentWindowController reads for its on-demand per-extension
		// prompt.
		//
		// identifier has unspecified nullability in the header, so it imports
		// as String!, and satisfying installBundleIdentifiers's [String]
		// parameters needs it unwrapped one way or another. compactMap drops
		// any nil rather than force-unwrapping: every TMBundleChoice comes
		// from -availableBundles, which always passes a real identifier
		// string (spec.uuid.UUIDString, and BundleSpec.mm:21 refuses to
		// construct a spec with no uuid) into the factory method, so this is
		// an identical result today -- but a first-launch wizard is the worst
		// place for a future producer of TMBundleChoice to crash the app over
		// a nil identifier instead of just omitting one bundle.
		let offered = allBundles.filter { !$0.installed }
		let install = offered.filter { checkedBundleIdentifiers.contains($0.identifier) }.compactMap { $0.identifier }
		let never   = offered.filter { !checkedBundleIdentifiers.contains($0.identifier) }.compactMap { $0.identifier }
		host.installBundleIdentifiers(install, neverSuggest: never)

		host.finish(withSkip: false)
	}

	func skip()   { host.finish(withSkip: true) }
}

struct SetupAssistantView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 16) {
				Text(model.step.title).font(.largeTitle.bold())

				switch model.step {
					case .welcome:    WelcomeStepView()
					case .appearance: AppearanceStepView(model: model)
					case .bundles:    BundlesStepView(model: model)
				}

				Spacer()
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(24)

			Divider()

			HStack {
				// ESC skips, which is what the assistant's own copy and the
				// spec both promise. Without .cancelAction the key does
				// nothing at all in a modal session.
				Button("Skip Setup") { model.skip() }
					.keyboardShortcut(.cancelAction)
				Spacer()
				if !model.isFirstStep {
					Button("Back") { model.back() }
				}
				Button(model.isLastStep ? "Done" : "Continue") {
					model.isLastStep ? model.finish() : model.advance()
				}
				.keyboardShortcut(.defaultAction)
			}
			.padding(16)
		}
		.frame(minWidth: 640, minHeight: 460)
	}
}

struct AppearanceStepView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Picker("Appearance", selection: $model.appearance) {
				Text("Light").tag("light")
				Text("Dark").tag("dark")
				Text("Automatic").tag("auto")
			}
			.pickerStyle(.segmented)
			.frame(maxWidth: 320)

			// Automatic uses both themes, so both have to be reachable. This
			// is the whole of that: one extra picker, shown only when it means
			// something, choosing which slot the one list below is editing.
			if model.appearance == "auto" {
				Picker("Editing", selection: $model.editingSlot) {
					Text("Light Theme").tag("light")
					Text("Dark Theme").tag("dark")
				}
				.pickerStyle(.segmented)
				.frame(maxWidth: 320)
			}

			HStack(alignment: .top, spacing: 16) {
				List(model.themes(for: model.editingAppearance), id: \.identifier, selection: model.selectedThemeBinding) { theme in
					Text(theme.name).tag(theme.identifier)
				}
				.frame(width: 220)

				ThemePreview(theme: model.selectedTheme)
					.frame(maxWidth: .infinity, minHeight: 200)
			}
		}
	}
}

struct BundlesStepView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Bundles add language support, commands and snippets.")
				.foregroundStyle(.secondary)

			// Every shipped-tier bundle is listed regardless of install
			// state, so this is empty only when there are no shipped-tier
			// bundles at all -- in practice unreachable. Kept rather than
			// deleted: a step that silently renders nothing is worse than
			// one with an explicit, if unlikely, empty message.
			if model.bundles.isEmpty {
				Text("There are no bundles available to offer here.")
					.foregroundStyle(.secondary)
			}
			else {
				// Unchecking is not "not now": installBundleIdentifiers:neverSuggest:
				// adds the bundle to the never-suggest list, which also silences
				// the on-demand prompt when a matching file is opened. The window
				// this replaced said as much in its subtitle. Installed bundles
				// show as already set up; they are checked but their toggle is
				// disabled below, so they can never end up in the unchecked set
				// this disclosure describes.
				Text("Installed bundles are already set up. Recommended ones are pre-selected — unchecked bundles will not be suggested again, not even when you open a file that needs one — you can still install them later from Preferences › Bundles.")
					.foregroundStyle(.secondary)

				List(model.bundles, id: \.identifier) { bundle in
					Toggle(isOn: model.binding(for: bundle)) {
						VStack(alignment: .leading, spacing: 2) {
							Text(bundle.name)
							Text(bundle.category).font(.caption).foregroundStyle(.secondary)
						}
					}
					.disabled(bundle.installed)
				}
			}
		}
	}
}

// A mockup, not a live editor. Rendering real text would need the C++ theme
// and layout frameworks, neither of which can cross the bridging header. The
// colours are real; the code is fake.
struct ThemePreview: View {
	let theme: TMThemeChoice?

	private func color(_ key: String, _ fallback: Color) -> Color {
		guard let value = theme?.colors[key] else { return fallback }
		return Color(nsColor: value)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			line([("# frobnicate the widget", TMThemeColorComment)])
			line([("def ", TMThemeColorKeyword), ("frobnicate", TMThemeColorFunction), ("(count)", TMThemeColorForeground)])
			line([("  raise ", TMThemeColorKeyword), ("\"too many\"", TMThemeColorString), (" if count > ", TMThemeColorForeground), ("42", TMThemeColorNumber)])
			line([("  count * ", TMThemeColorForeground), ("2", TMThemeColorNumber)])
			line([("end", TMThemeColorKeyword)])
		}
		.font(.system(.body, design: .monospaced))
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(color(TMThemeColorBackground, .black))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private func line(_ runs: [(String, String)]) -> some View {
		runs.reduce(Text("")) { partial, run in
			partial + Text(run.0).foregroundColor(color(run.1, .white))
		}
	}
}

struct WelcomeStepView: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("TextMate Revived is a fork of TextMate for macOS 26 on Apple Silicon.")
			Text("This assistant sets up how the editor looks and which bundles you have. You can run it again at any time from the Help menu.")
				.foregroundStyle(.secondary)
		}
	}
}

// The Objective-C++ entry point. `public` is load-bearing: an internal @objc
// declaration compiles, reaches the .swiftmodule, and is silently absent from
// the generated TextMate-Swift.h.
@objc(SetupAssistantHostingController)
public final class SetupAssistantHostingController: NSObject {
	// Objective-C has no notion of actor isolation, so this must state its own:
	// it constructs SetupAssistantModel, which is @MainActor, and NSHostingView's
	// initializer is @MainActor too. The window controller that calls this always
	// does so on the main thread (AppKit window/UI construction), so the
	// isolation this declares matches the isolation the caller is already on.
	@MainActor
	@objc public static func view(for host: any TMSetupAssistantHost) -> NSView {
		return NSHostingView(rootView: SetupAssistantView(model: SetupAssistantModel(host: host)))
	}
}
