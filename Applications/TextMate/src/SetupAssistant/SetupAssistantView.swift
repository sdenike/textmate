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

	let host: any TMSetupAssistantHost

	init(host: any TMSetupAssistantHost) {
		self.host = host
	}

	var isFirstStep: Bool { step == .welcome }
	var isLastStep: Bool  { step == .bundles }

	func back() {
		guard let previous = TMSetupAssistantStep(rawValue: step.rawValue - 1) else { return }
		step = previous
	}

	func advance() {
		guard let next = TMSetupAssistantStep(rawValue: step.rawValue + 1) else { return }
		step = next
	}

	func finish() { host.finish(withSkip: false) }
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
					case .appearance: Text("Appearance")     // Task 6
					case .bundles:    Text("Bundles")        // Task 7
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
