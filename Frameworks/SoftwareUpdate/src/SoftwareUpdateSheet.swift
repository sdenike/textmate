// Frameworks/SoftwareUpdate/src/SoftwareUpdateSheet.swift
import AppKit
import SwiftUI

// One button in the sheet's button row. A value, not a live NSButton --
// SUDownloadViewController rebuilds this array whenever the sheet's state
// changes rather than mutating an existing NSButton's title/enabled/action in
// place, the way the old addButtonWithTitle:/didClickButton: pair did.
// `action` is the only part of this that is not pure data; the shape
// (title/enabled/isDefault/isCancel) is built from SUButtonSpec
// (SUButtonSpec.h), which t_SUButtonSpec.mm exercises without any window or
// SwiftUI view involved.
@objc(SoftwareUpdateButtonModel)
public final class SoftwareUpdateButtonModel: NSObject, Identifiable {
	public let id = UUID()
	@objc public let title: String
	@objc public let enabled: Bool
	@objc public let isDefault: Bool
	@objc public let isCancel: Bool
	let action: () -> Void

	@objc public init(title: String, enabled: Bool, isDefault: Bool, isCancel: Bool, action: @escaping () -> Void) {
		self.title = title
		self.enabled = enabled
		self.isDefault = isDefault
		self.isCancel = isCancel
		self.action = action
		super.init()
	}
}

// The sheet's whole visible state. SUDownloadViewController replaces this
// wholesale on every transition (New Version Available -> Downloading ->
// Downloaded, etc.), the same way TerminalPane.swift's SettingsPaneMateInstall
// is pushed a finished snapshot rather than mutated field by field -- there is
// no per-property setter here for the same reason there is no per-button
// mutation: a state is everything it shows, not a diff against the last one.
//
// @MainActor because it drives SwiftUI. Both call sites that push into it are
// main-thread already, unlike SoftwareUpdatePreferences.pushUpdateStatus's KVO
// chain: OakDownloadManager.mm creates its NSURLSession with
// delegateQueue:NSOperationQueue.mainQueue, so both the download completion
// handler and (because it is armed from inside that same main-thread call)
// the NSProgress poll timer both already run on main. See SoftwareUpdate.mm
// for the specific trace of each. Do not add a dispatch_async here to guard
// against an off-main caller that does not exist -- SettingsPaneVariables and
// SettingsPaneFileBrowserLocation skip that guard for the identical reason.
@objc(SoftwareUpdateSheetModel)
@MainActor
public final class SoftwareUpdateSheetModel: NSObject, ObservableObject {
	@Published var messageText: String = ""
	@Published var informativeText: String = ""
	@Published var showsProgress: Bool = false
	@Published var progressFraction: Double = 0
	@Published var isIndeterminate: Bool = false
	@Published var buttons: [SoftwareUpdateButtonModel] = []

	@objc public override init() {
		super.init()
	}

	@objc public func show(message: String, informative: String, buttons: [SoftwareUpdateButtonModel]) {
		messageText = message
		informativeText = informative
		showsProgress = false
		self.buttons = buttons
	}

	@objc public func showProgress(message: String, informative: String, fraction: Double, indeterminate: Bool, buttons: [SoftwareUpdateButtonModel]) {
		messageText = message
		informativeText = informative
		showsProgress = true
		progressFraction = fraction
		isIndeterminate = indeterminate
		self.buttons = buttons
	}
}

private struct SoftwareUpdateContentView: View {
	@ObservedObject var model: SoftwareUpdateSheetModel

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(model.messageText)
				.fontWeight(.bold)
			if model.showsProgress {
				ProgressView(value: model.isIndeterminate ? nil : model.progressFraction)
				// .monospacedDigit(), not a monospaced font: the old
				// SUProgressViewController used
				// NSFont.monospacedDigitSystemFontOfSize:weight: specifically so
				// the counting digits do not jitter the layout width as they
				// change, while words like "remaining" stay proportional --
				// a fully monospaced design would look like a terminal.
				//
				// .fixedSize(): labelWithString: (not wrappingLabelWithString:)
				// in the old SUProgressViewController -- a single line that
				// grows the window rather than wrapping, same as here.
				Text(model.informativeText)
					.font(.callout)
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.fixedSize()
			} else {
				// wrappingLabelWithString: in the old SUInfoViewController.
				// Wrapping needs an actual width to wrap AGAINST -- a bare
				// minWidth on the VStack below is a floor, not a ceiling, so
				// without this the sentence rendered as one very wide line
				// instead of wrapping at 298 (measured: an 804pt-wide window
				// for "New Version Available" before this fix).
				Text(model.informativeText)
					.frame(width: 298, alignment: .leading)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		// 298 and 376 (298 plus SUProgressViewController's own "+20" margin)
		// are not arbitrary: they are the real fittingSize.width, measured
		// against this SDK, of the two longest strings either state ever
		// shows -- "Would you like to download and install?" at the info
		// controller's bold-body/message font, and the progress placeholder
		// "999.9 MB of 999.9 MB -- About 59 minutes, 59 seconds remaining" at
		// the monospaced-digit small system font. The progress column is a
		// MINIMUM (matches the old >= constraint: a longer string is allowed
		// to grow the window) so a downloading percentage tick does not
		// resize the window every 40ms for the common case; the info column
		// is exact, matching the old view's == constraint, because it is what
		// makes the sentence above wrap instead of running wide.
		.frame(minWidth: model.showsProgress ? 376 : 298, alignment: .leading)
	}
}

private struct SoftwareUpdateButtonsRow: View {
	@ObservedObject var model: SoftwareUpdateSheetModel

	var body: some View {
		HStack(spacing: 16) {
			Spacer(minLength: 20)
			// Reversed. SoftwareUpdate.mm builds `buttons` in the same order
			// the AppKit version called addButtonWithTitle: -- primary action
			// first, e.g. ["Download", "Cancel"] -- and measuring real AppKit
			// (NSStackView, two buttons inserted via
			// insertView:atIndex:0 inGravity:NSStackViewGravityTrailing, which
			// is what addButtonWithTitle: did) shows the FIRST one added ends
			// up rightmost, not leftmost. Reversing the array for display
			// reproduces that ordering -- primary action rightmost, exactly
			// like a standard AppKit alert -- without carrying an NSStackView
			// into SwiftUI.
			ForEach(Array(model.buttons.reversed())) { button in
				Button(button.title, action: button.action)
					.disabled(!button.enabled)
					.keyboardShortcut(button.isDefault ? .defaultAction : (button.isCancel ? .cancelAction : nil))
					.frame(minWidth: 86)
			}
		}
	}
}

struct SoftwareUpdateSheetView: View {
	@ObservedObject var model: SoftwareUpdateSheetModel
	let icon: NSImage

	var body: some View {
		HStack(alignment: .top, spacing: 16) {
			Image(nsImage: icon)
				.resizable()
				.frame(width: 64, height: 64)
			VStack(alignment: .leading, spacing: 20) {
				SoftwareUpdateContentView(model: model)
				SoftwareUpdateButtonsRow(model: model)
			}
		}
		.padding(EdgeInsets(top: 16, leading: 24, bottom: 18, trailing: 20))
	}
}

@objc(SoftwareUpdateViewFactory)
public final class SoftwareUpdateViewFactory: NSObject {
	// `public`, not merely @objc -- CLAUDE.md's Swift section: an internal
	// @objc class compiles and lands in the .swiftmodule but is simply absent
	// from the generated -Swift.h, and the ObjC++ call site then fails with
	// "use of undeclared identifier", which reads like a typo rather than an
	// access-level mistake.
	@MainActor
	@objc public static func makeSheetView(model: SoftwareUpdateSheetModel, icon: NSImage) -> NSView {
		let view = NSHostingView(rootView: SoftwareUpdateSheetView(model: model, icon: icon))
		// Same fittingSize discipline as every other hosted view in this tree
		// (SettingsPaneFactory, TerminalPane.swift): a fresh NSHostingView
		// measures 0x0 until told its frame. SUDownloadViewController
		// re-measures this same way after every later state change --
		// see -resizeToFitContent.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
