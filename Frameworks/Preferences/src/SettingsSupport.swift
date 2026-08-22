// Frameworks/Preferences/src/SettingsSupport.swift
import Foundation
import SwiftUI

// All three channels the app defines. Nightly is offered at the maintainer's
// direction; Task 3 changes SoftwareUpdate.mm:392 so it actually differs from
// release. Until a nightly tag stream exists it delivers the same updates as
// prerelease -- the feed is git tags with two tiers.
public enum SettingsChannel: String, CaseIterable, Identifiable {
	case release
	case prerelease
	case nightly

	public var id: String { rawValue }

	// The stored defaults value. Not the case name: prerelease persists as "beta"
	// and nightly as "nightly".
	public var storedValue: String {
		switch self {
			case .release:    return kSoftwareUpdateChannelRelease
			case .prerelease: return kSoftwareUpdateChannelPrerelease
			case .nightly:    return kSoftwareUpdateChannelCanary
		}
	}

	public var title: String {
		switch self {
			case .release:    return "Normal releases"
			case .prerelease: return "Prereleases"
			case .nightly:    return "Nightly builds"
		}
	}

	// Unrecognised values fall back to release, which is what an unknown channel
	// delivers -- SoftwareUpdate.mm:363 looks the channel up in a dictionary and
	// errors if it is missing.
	public static func from(storedValue: String?) -> SettingsChannel {
		allCases.first { $0.storedValue == storedValue } ?? .release
	}
}

@MainActor
final class SoftwareUpdateModel: ObservableObject {
	// Stored inverted in defaults: the key disables polling, the checkbox enables
	// it. The old code expressed this as NSNegateBooleanTransformerName inside a
	// binding, where it was invisible unless you read the options dictionary.
	@AppStorage(kUserDefaultsDisableSoftwareUpdateKey) private var pollingDisabled: Bool = false
	@AppStorage(kUserDefaultsAskBeforeUpdatingKey)     var askBeforeDownloading: Bool = false
	@AppStorage(kUserDefaultsSoftwareUpdateChannelKey) private var channelRaw: String = kSoftwareUpdateChannelRelease

	var watchForUpdates: Bool {
		get { !pollingDisabled }
		set { pollingDisabled = !newValue }
	}

	var channel: SettingsChannel {
		get { SettingsChannel.from(storedValue: channelRaw) }
		set { channelRaw = newValue.storedValue }
	}
}

// Pushed from SoftwareUpdatePreferences's own KVO, not polled. The ObjC side
// already declares +keyPathsForValuesAffectingLastCheckDescription over
// softwareUpdateController.checking, .errorString and relativeStringForLastCheck,
// so observing that one derived property on self is enough to catch all three,
// and this is where it hands the result across the bridge. @MainActor because
// it drives SwiftUI, and NOT because the KVO chain is main-thread -- it is not.
// SoftwareUpdate.mm's NSBackgroundActivityScheduler block runs the synchronous
// `self.checking = YES` on an XPC activity queue, so -pushUpdateStatus hops to
// the main queue before calling in here. Do not relax this isolation to make
// that call site compile: the @objc thunk of a @MainActor method SIGTRAPs when
// invoked off-main.
@objc(SettingsPaneUpdateStatus)
@MainActor
public final class SettingsPaneUpdateStatus: NSObject, ObservableObject {
	@Published var lastCheckDescription: String = ""
	@Published var isChecking: Bool = false

	@objc public override init() {
		super.init()
	}

	@objc public func update(lastCheckDescription: String, isChecking: Bool) {
		self.lastCheckDescription = lastCheckDescription
		self.isChecking = isChecking
	}
}

struct SoftwareUpdatePaneView: View {
	@ObservedObject var model: SoftwareUpdateModel
	@ObservedObject var status: SettingsPaneUpdateStatus
	let checkNow: () -> Void

	var body: some View {
		SettingsPane {
			Section {
				Toggle("Watch for updates", isOn: Binding(get: { model.watchForUpdates },
				                                          set: { model.watchForUpdates = $0 }))
				Picker("Channel", selection: Binding(get: { model.channel },
				                                     set: { model.channel = $0 })) {
					ForEach(SettingsChannel.allCases) { channel in
						Text(channel.title).tag(channel)
					}
				}
				.disabled(!model.watchForUpdates)

				Toggle("Ask before downloading updates", isOn: $model.askBeforeDownloading)
					.disabled(!model.watchForUpdates)
			}

			Section {
				LabeledContent("Last check", value: status.lastCheckDescription)
				Button("Check Now", action: checkNow)
					.disabled(status.isChecking)
			}
		}
	}
}

// MARK: - Projects pane

// Plain data handed across from ObjC++: title, icon (already sized to 16x16
// or nil when NSURLEffectiveIconKey failed) and a url string, following how
// SoftwareUpdatePreferences hands its host state across. A Swift *struct*
// cannot cross the bridge, so this is a class -- ProjectsPreferences.mm
// constructs one per menu entry the exact way -updatePathPopUp used to build
// an NSMenuItem, including the two synthetic rows (separator, "Other…") that
// carry no url. isSeparator/isOther distinguish those from a real location
// without overloading url's emptiness (a real location's absoluteString is
// never empty, but nothing enforces that at this layer).
@objc(SettingsFileBrowserLocationItem)
public final class SettingsFileBrowserLocationItem: NSObject {
	@objc public let title: String
	@objc public let icon: NSImage?
	@objc public let url: String
	@objc public let isSeparator: Bool
	@objc public let isOther: Bool

	@objc public init(title: String, icon: NSImage?, url: String, isSeparator: Bool, isOther: Bool) {
		self.title = title
		self.icon = icon
		self.url = url
		self.isSeparator = isSeparator
		self.isOther = isOther
		super.init()
	}
}

// Pushed from ProjectsPreferences the same way SettingsPaneUpdateStatus is:
// ObjC++ owns the real state (NSUserDefaults plus AppKit APIs SwiftUI cannot
// reach -- icons, displayNameAtPath:, NSOpenPanel) and calls -update whenever
// it changes. @MainActor for the same reason as SettingsPaneUpdateStatus: it
// drives SwiftUI, and every caller (-loadView, the NSOpenPanel sheet's
// completion handler) is already on the main thread, unlike SoftwareUpdate's
// background-queue KVO. Do not relax this isolation to paper over a call site
// that turns out not to be main-thread -- fix the call site instead.
@objc(SettingsPaneFileBrowserLocation)
@MainActor
public final class SettingsPaneFileBrowserLocation: NSObject, ObservableObject {
	@Published var items: [SettingsFileBrowserLocationItem] = []
	@Published var selectedIndex: Int = 0

	@objc public override init() {
		super.init()
	}

	@objc public func update(items: [SettingsFileBrowserLocationItem], selectedIndex: Int) {
		self.items = items
		self.selectedIndex = selectedIndex
	}
}

struct ProjectsPaneView: View {
	// Plain NSUserDefaults-backed values. Deliberately @AppStorage directly on
	// this View rather than wrapped in a helper ObservableObject (contrast
	// SoftwareUpdateModel): @AppStorage only gets SwiftUI's automatic
	// re-render hook when it is a stored property of a View/App/Scene --
	// wrapping it in a plain ObservableObject class does not reliably signal
	// objectWillChange, since ObservableObject's synthesised publisher only
	// fires for @Published. SoftwareUpdatePaneView's toggles are steered clear
	// of this by a side effect (its `status` object republishes on every
	// NSUserDefaultsDidChangeNotification, forcing a re-render that happens to
	// re-read the model fresh); this pane has no equivalent side channel, so
	// it does not lean on one.
	@AppStorage(kUserDefaultsFoldersOnTopKey)                  private var foldersOnTop = false
	@AppStorage(kUserDefaultsAllowExpandingLinksKey)           private var allowExpandingLinks = false
	@AppStorage(kUserDefaultsFileBrowserSingleClickToOpenKey)  private var fileBrowserSingleClickToOpen = false
	@AppStorage(kUserDefaultsAutoRevealFileKey)                private var autoRevealFile = false
	@AppStorage(kUserDefaultsFileBrowserPlacementKey)          private var fileBrowserPlacementRaw = "right"
	@AppStorage(kUserDefaultsDisableFileBrowserWindowResizeKey) private var disableAutoResize = false
	@AppStorage(kUserDefaultsDisableTabBarCollapsingKey)       private var disableTabBarCollapsing = false
	@AppStorage(kUserDefaultsDisableTabReorderingKey)          private var disableTabReordering = false
	@AppStorage(kUserDefaultsDisableTabAutoCloseKey)           private var disableTabAutoClose = false
	@AppStorage(kUserDefaultsHTMLOutputPlacementKey)           private var htmlOutputPlacementRaw = "window"

	// settings_t-backed, not defaults-backed -- there is no @AppStorage
	// equivalent, so these are seeded once from TMSettingsGetString and pushed
	// back through TMSettingsSetString on every edit.
	@State private var excludePattern = TMSettingsGetString(TMSettingsExcludeKey())
	@State private var includePattern = TMSettingsGetString(TMSettingsIncludeKey())
	@State private var binaryPattern  = TMSettingsGetString(TMSettingsBinaryKey())

	@ObservedObject var fileBrowserLocation: SettingsPaneFileBrowserLocation
	let onSelectLocation: (String) -> Void

	var body: some View {
		SettingsPane {
			Section {
				Picker("File browser location:", selection: locationSelectionBinding) {
					ForEach(Array(fileBrowserLocation.items.enumerated()), id: \.offset) { index, item in
						if item.isSeparator {
							Divider()
						} else if let icon = item.icon {
							Label(title: { Text(item.title) }, icon: { Image(nsImage: icon) }).tag(index)
						} else {
							Text(item.title).tag(index)
						}
					}
				}
				Toggle("Folders on top", isOn: $foldersOnTop)
				Toggle("Show links as expandable", isOn: $allowExpandingLinks)
				Toggle("Open files on single click", isOn: $fileBrowserSingleClickToOpen)
				Toggle("Keep current document selected", isOn: $autoRevealFile)
			}

			Section {
				Picker("Show file browser on:", selection: fileBrowserPlacementTagBinding) {
					Text("Left side").tag(0)
					Text("Right side").tag(1)
				}
				Toggle("Adjust window when toggleing display", isOn: adjustWindowOnToggleBinding)
			}

			Section {
				Toggle("Show for single document", isOn: $disableTabBarCollapsing)
				Toggle("Re-order when opening a file", isOn: reorderWhenOpeningAFileBinding)
				Toggle("Automatically close unused tabs", isOn: automaticallyCloseUnusedTabsBinding)
			}

			Section {
				TextField("Exclude files matching:", text: excludePatternBinding)
				TextField("Include files matching:", text: includePatternBinding)
				TextField("Non-text files:", text: binaryPatternBinding)
			}

			Section {
				Picker("Show command output:", selection: htmlOutputPlacementTagBinding) {
					Text("Below text view").tag(0)
					Text("Right of text view").tag(1)
					Text("New window").tag(2)
				}
			}
		}
	}

	// selectedIndex/items are always replaced together by -update, so a raw
	// array index is a safe, stable tag for the lifetime of one such pair --
	// the only mutation is ObjC++ calling -update again with a fresh pair.
	private var locationSelectionBinding: Binding<Int> {
		Binding(get: { fileBrowserLocation.selectedIndex }, set: { newIndex in
			guard fileBrowserLocation.items.indices.contains(newIndex) else { return }
			onSelectLocation(fileBrowserLocation.items[newIndex].url)
		})
	}

	private var fileBrowserPlacementTagBinding: Binding<Int> {
		Binding(
			get: { Int(TMFileBrowserPlacementTagForValue(fileBrowserPlacementRaw)) },
			set: { fileBrowserPlacementRaw = TMFileBrowserPlacementValueForTag(NSInteger($0)) }
		)
	}

	private var htmlOutputPlacementTagBinding: Binding<Int> {
		Binding(
			get: { Int(TMHTMLOutputPlacementTagForValue(htmlOutputPlacementRaw)) },
			set: { htmlOutputPlacementRaw = TMHTMLOutputPlacementValueForTag(NSInteger($0)) }
		)
	}

	// Three checkboxes are negated: the label is phrased positively against a
	// key named disable…, and getting one backwards silently inverts a user's
	// setting while the UI still looks right.
	private var adjustWindowOnToggleBinding: Binding<Bool> {
		Binding(get: { !disableAutoResize }, set: { disableAutoResize = !$0 })
	}

	private var reorderWhenOpeningAFileBinding: Binding<Bool> {
		Binding(get: { !disableTabReordering }, set: { disableTabReordering = !$0 })
	}

	private var automaticallyCloseUnusedTabsBinding: Binding<Bool> {
		Binding(get: { !disableTabAutoClose }, set: { disableTabAutoClose = !$0 })
	}

	private var excludePatternBinding: Binding<String> {
		Binding(get: { excludePattern }, set: { excludePattern = $0; TMSettingsSetString(TMSettingsExcludeKey(), $0) })
	}

	private var includePatternBinding: Binding<String> {
		Binding(get: { includePattern }, set: { includePattern = $0; TMSettingsSetString(TMSettingsIncludeKey(), $0) })
	}

	private var binaryPatternBinding: Binding<String> {
		Binding(get: { binaryPattern }, set: { binaryPattern = $0; TMSettingsSetString(TMSettingsBinaryKey(), $0) })
	}
}

@objc(SettingsPaneFactory)
public final class SettingsPaneFactory: NSObject {
	// `public`, not merely @objc: an internal @objc class is absent from the
	// generated Preferences-Swift.h and fails at the ObjC++ call site with
	// "use of undeclared identifier", pointing at the wrong file entirely.
	@MainActor
	@objc public static func softwareUpdateView(checkNow: @escaping () -> Void, status: SettingsPaneUpdateStatus) -> NSView {
		let model = SoftwareUpdateModel()
		let view = NSHostingView(rootView: SoftwareUpdatePaneView(model: model, status: status, checkNow: checkNow))
		// PreferencesPane.mm:36 sizes a pane from its fittingSize, and
		// OakTransitionViewController pins to it. A 0x0 here is what made the
		// Terminal pane look like a dead click for months. status is seeded by
		// the caller before this runs, so this measures real text, not "".
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}

	@MainActor
	@objc public static func projectsView(fileBrowserLocation: SettingsPaneFileBrowserLocation, onSelectLocation: @escaping (String) -> Void) -> NSView {
		let view = NSHostingView(rootView: ProjectsPaneView(fileBrowserLocation: fileBrowserLocation, onSelectLocation: onSelectLocation))
		// Same fittingSize discipline as softwareUpdateView: fileBrowserLocation
		// is seeded by the caller (ProjectsPreferences -loadView) before this
		// runs, so the Picker measures its real first item, not an empty menu.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
