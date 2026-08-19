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
	@Published var selectedThemeIdentifier: String?
	@Published var checkedBundleIdentifiers: Set<String> = []

	let host: any TMSetupAssistantHost

	private lazy var allThemes: [TMThemeChoice] = host.availableThemes()

	private lazy var allBundles: [TMBundleChoice] = host.availableBundles()
	var bundles: [TMBundleChoice] { allBundles }

	init(host: any TMSetupAssistantHost) {
		self.host = host
		self.appearance = host.currentAppearance() ?? "auto"
		self.selectedThemeIdentifier = host.currentThemeIdentifier(forAppearance: editingAppearance)
		self.checkedBundleIdentifiers = Set(allBundles.filter { $0.recommended && !$0.installed }.map { $0.identifier })
	}

	var isFirstStep: Bool { step == .welcome }
	var isLastStep: Bool  { step == .bundles }

	// In automatic mode both keys are used, so the user edits the light theme
	// here; the dark one keeps whatever it already had.
	var editingAppearance: String { appearance == "dark" ? "dark" : "light" }

	func themes(for appearance: String) -> [TMThemeChoice] {
		allThemes.filter { $0.appearance == appearance || $0.appearance == "unspecified" }
	}

	var selectedTheme: TMThemeChoice? {
		allThemes.first { $0.identifier == selectedThemeIdentifier }
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
		if let identifier = selectedThemeIdentifier {
			host.applyThemeIdentifier(identifier, appearance: editingAppearance)
		}
		// The tri-state picker (light/dark/auto) is distinct from
		// editingAppearance above, which is only ever "light" or "dark" --
		// it picks which slot's theme list to show, and collapses "auto" to
		// "light" for that purpose. Only this call can carry "auto" itself
		// through to the "themeAppearance" default, so Automatic has a real
		// effect instead of being indistinguishable from Light.
		host.applyAppearance(appearance == "auto" ? nil : appearance)

		// -availableBundles never actually hands back an installed one today
		// (FirstLaunchBundleInstaller.candidateSpecs excludes them at the
		// source), but filtering here too means this stays correct even if
		// that changes, rather than silently re-installing or re-declining
		// something already on disk.
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
				Button("Skip Setup") { model.skip() }
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

			HStack(alignment: .top, spacing: 16) {
				List(model.themes(for: model.editingAppearance), id: \.identifier, selection: $model.selectedThemeIdentifier) { theme in
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
			Text("Bundles add language support, commands and snippets. Recommended ones are already selected.")
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
