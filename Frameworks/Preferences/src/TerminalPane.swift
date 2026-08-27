// Frameworks/Preferences/src/TerminalPane.swift
import Foundation
import SwiftUI

// MARK: - Shell support state

// Pushed from TerminalPreferences the same way SettingsPaneUpdateStatus and
// SettingsPaneFileBrowserLocation are: ObjC++ owns the real state (defaults,
// filesystem checks, format_string::expand, the privileged install machinery)
// and calls -update whenever any of it changes. @MainActor because it drives
// SwiftUI, and every caller (-loadView, the popup selection callback, the
// NSSavePanel and NSAlert completion handlers, install/uninstall) is already
// on the main thread -- there is no background queue in this pane the way
// SoftwareUpdate's polling timer has.
@objc(SettingsPaneMateInstall)
@MainActor
public final class SettingsPaneMateInstall: NSObject, ObservableObject {
	@Published var statusText: String = ""
	@Published var summaryText: String = ""
	@Published var isInstalled: Bool = false
	@Published var statusImage: NSImage = NSImage()
	@Published var pathItems: [TMInstallPathItem] = []
	@Published var selectedPathIndex: Int = 0

	@objc public override init() {
		super.init()
	}

	@objc public func update(statusText: String, summaryText: String, isInstalled: Bool, statusImage: NSImage, pathItems: [TMInstallPathItem], selectedPathIndex: Int) {
		self.statusText = statusText
		self.summaryText = summaryText
		self.isInstalled = isInstalled
		self.statusImage = statusImage
		self.pathItems = pathItems
		self.selectedPathIndex = selectedPathIndex
	}
}

// MARK: - Help button

// The corner help button, built and fully configured (target, action,
// bezelStyle, and the alternateTitle PreferencesPane.help: reads as the anchor)
// by TerminalPreferences.mm itself and merely HOSTED here -- see that file's
// -loadView for why: help: is inherited from PreferencesPane, is not visible
// to Swift, and reimplementing it would mean guessing whether the responder
// chain reaches this view controller instead of just wiring the real button's
// target to self, which is unambiguous.
private struct HelpButtonHost: NSViewRepresentable {
	let button: NSButton

	func makeNSView(context: Context) -> NSButton { button }
	func updateNSView(_ nsView: NSButton, context: Context) {}
}

// MARK: - Terminal pane

struct TerminalPaneView: View {
	@ObservedObject var model: SettingsPaneMateInstall
	let helpButton: NSButton
	let onSelectPath: (String) -> Void
	let onInstallOrUninstall: () -> Void

	// Plain NSUserDefaults-backed, exactly like the Projects/Files panes'
	// un-wrapped @AppStorage fields -- nothing here needs transforming except
	// the negation on the checkbox.
	@AppStorage(kUserDefaultsDisableRMateServerKey) private var disableRMate = false
	@AppStorage(kUserDefaultsRMateServerListenKey)  private var rmateInterface = kRMateServerListenLocalhost
	@AppStorage(kUserDefaultsRMateServerPortKey)    private var rmatePort = "52698"

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			SettingsPane {
				Section {
					Label {
						Text(model.statusText).bold()
					} icon: {
						Image(nsImage: model.statusImage)
					}
					Text(model.summaryText)
						.frame(maxWidth: 400, alignment: .leading)
						.fixedSize(horizontal: false, vertical: true)
					Picker("Location:", selection: pathSelectionBinding) {
						ForEach(Array(model.pathItems.enumerated()), id: \.offset) { index, item in
							if item.isSeparator {
								Divider()
							} else {
								Text(item.title).tag(index)
							}
						}
					}
					.disabled(model.isInstalled)
					Button(model.isInstalled ? "Uninstall" : "Install", action: onInstallOrUninstall)
				}

				Section {
					Toggle("Accept rmate connections", isOn: acceptRMateBinding)
					Picker("Access for:", selection: $rmateInterface) {
						Text("local clients").tag(kRMateServerListenLocalhost)
						Text("remote clients").tag(kRMateServerListenRemote)
					}
					.disabled(disableRMate)
					TextField("Port:", text: $rmatePort)
						.disabled(disableRMate)
					Text(rmateSummaryAttributedString)
						.frame(maxWidth: 400, alignment: .leading)
						.fixedSize(horizontal: false, vertical: true)
				}
			}

			HelpButtonHost(button: helpButton)
				.fixedSize()
				.padding(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 0))
		}
	}

	// Int tags via enumerated offset, same shape as ProjectsPaneView's
	// locationSelectionBinding: the Picker needs a stable Hashable tag, and the
	// callback that reaches ObjC++ hands back a resolved semantic value rather
	// than an index -- "" for the synthetic Other… row (never a real path,
	// exactly the convention SettingsFileBrowserLocationItem's url uses), the
	// item's title otherwise. ObjC++ never has to know about array indices.
	private var pathSelectionBinding: Binding<Int> {
		Binding(get: { model.selectedPathIndex }, set: { newIndex in
			guard model.pathItems.indices.contains(newIndex) else { return }
			let item = model.pathItems[newIndex]
			onSelectPath(item.isOther ? "" : item.title)
		})
	}

	// disableRMate is a NEGATED default: the checkbox reads "Accept rmate
	// connections" (positive) against a key named rmateServerDisabled. Losing
	// this negation silently inverts the setting while the checkbox still
	// looks right -- see AppController.mm:481, which reads the same key
	// straight (un-negated) as "disableRmate" when it starts the real server.
	private var acceptRMateBinding: Binding<Bool> {
		Binding(get: { !disableRMate }, set: { disableRMate = !$0 })
	}

	// The one word "rmate" in this paragraph is a link to the project's GitHub
	// page, exactly as CreateHyperLink built it on the AppKit side. Built as an
	// AttributedString rather than Markdown syntax in the source string: this
	// text is copied byte-for-byte out of the old xib specifically so it is not
	// retyped, and marking up the link inline would mean editing those bytes.
	private var rmateSummaryAttributedString: AttributedString {
		var text = AttributedString("If you wish to activate TextMate from an ssh session you can do so by copying the rmate script to the server you are logged into. The script will connect back to TextMate so you need to either allow access for remote clients (and setup your router to accept the specified port) or create an ssh tunnel. Use the help button in the corner for more information.")
		if let range = text.range(of: "rmate") {
			text[range].link = URL(string: "https://github.com/textmate/rmate/")
		}
		return text
	}
}

extension SettingsPaneFactory {
	@MainActor
	@objc public static func terminalView(model: SettingsPaneMateInstall, helpButton: NSButton, onSelectPath: @escaping (String) -> Void, onInstallOrUninstall: @escaping () -> Void) -> NSView {
		let view = NSHostingView(rootView: TerminalPaneView(model: model, helpButton: helpButton, onSelectPath: onSelectPath, onInstallOrUninstall: onInstallOrUninstall))
		// Same fittingSize discipline as every other pane: OakTransitionViewController.mm:42
		// pins the pane to this, and model/helpButton are both seeded by the
		// caller (TerminalPreferences -loadView) before this runs, so this
		// measures the real status text and a real button, not empty ones --
		// exactly the gap that left this specific pane at 0x0 for months
		// (CLAUDE.md, "the Terminal pane appearing as a dead click").
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
