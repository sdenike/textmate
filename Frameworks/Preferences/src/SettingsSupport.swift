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

// SwiftUI cannot ask which window is hosting a view, and the Projects pane
// needs to know: it commits its text fields when that window closes. An empty
// NSView placed in .background reports the answer and adds no layout of its
// own. viewDidMoveToWindow rather than a poll, and a main-queue hop out of it
// because it fires mid-layout, where writing SwiftUI state is not allowed.
private final class HostWindowReporter: NSView {
	var onWindow: ((NSWindow?) -> Void)?

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		let hostWindow = window
		Task { @MainActor in self.onWindow?(hostWindow) }
	}
}

private struct HostWindowReader: NSViewRepresentable {
	let onWindow: (NSWindow?) -> Void

	func makeNSView(context: Context) -> HostWindowReporter {
		let view = HostWindowReporter(frame: .zero)
		view.onWindow = onWindow
		return view
	}

	func updateNSView(_ nsView: HostWindowReporter, context: Context) {
		nsView.onWindow = onWindow
	}
}

struct ProjectsPaneView: View {
	// Plain NSUserDefaults-backed values, held directly on this View. Wrapping
	// them in an ObservableObject the way SoftwareUpdateModel does would work
	// equally well: measured 2026-08-21 against this machine's SDK, one
	// @AppStorage property inside a plain ObservableObject fired
	// objectWillChange 6 times for 3 writes, so a wrapped pane does re-render.
	// (The comment that stood here claimed the opposite, and credited
	// SoftwareUpdatePaneView with a NSUserDefaultsDidChangeNotification side
	// channel it has never had -- SettingsPaneUpdateStatus, :73-87, observes
	// nothing at all and is written to only by -pushUpdateStatus.) Both shapes
	// work, so the rule is about what a value IS, not about redraws:
	// @AppStorage on the View when a key maps straight onto a control, and a
	// model object only when something must be transformed or pushed in from
	// ObjC++ -- which is the whole reason SoftwareUpdateModel exists, an
	// inverted key and two raw channel strings.
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
	// equivalent, so these are seeded once from TMSettingsGetString and written
	// back through TMSettingsSetString on COMMIT, never per keystroke. Measured
	// 2026-08-21 with a standalone SwiftUI harness: typing the 9 characters of
	// "*.{o,pyc}" into a TextField bound through a Binding.set called that
	// setter 30 times -- SwiftUI re-runs it about three times per keystroke,
	// not once. Every one of those would reach settings_t::set, which is two
	// full read_file parses plus a NON-ATOMIC truncate-and-rewrite of the
	// user's Global.tmProperties (settings.cc:444), so a crash inside any one
	// of the 30 leaves that file empty -- font, theme, soft wrap and every
	// other global setting gone, not just these three patterns. The AppKit pane
	// never did this: it bound with NSValueBinding and WITHOUT
	// NSContinuouslyUpdatesValueBindingOption, so it committed on end-editing.
	@State private var excludePattern = TMSettingsGetString(TMSettingsExcludeKey())
	@State private var includePattern = TMSettingsGetString(TMSettingsIncludeKey())
	@State private var binaryPattern  = TMSettingsGetString(TMSettingsBinaryKey())

	@FocusState private var focusedPattern: PatternField?
	@State private var hostWindow: NSWindow?

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

			// Header, not a bare group: every other group names its subject
			// through a Picker or TextField label, and this one has no control
			// to hang a label on -- the AppKit grid gave it an
			// OakCreateLabel(@"Document tabs:") row, and without it the user
			// reads "Show for single document" with no idea what "show".
			Section("Document tabs:") {
				Toggle("Show for single document", isOn: $disableTabBarCollapsing)
				Toggle("Re-order when opening a file", isOn: reorderWhenOpeningAFileBinding)
				Toggle("Automatically close unused tabs", isOn: automaticallyCloseUnusedTabsBinding)
			}

			Section {
				TextField("Exclude files matching:", text: $excludePattern)
					.focused($focusedPattern, equals: .exclude)
					.onSubmit { commitPattern(.exclude) }
				TextField("Include files matching:", text: $includePattern)
					.focused($focusedPattern, equals: .include)
					.onSubmit { commitPattern(.include) }
				TextField("Non-text files:", text: $binaryPattern)
					.focused($focusedPattern, equals: .binary)
					.onSubmit { commitPattern(.binary) }
			}

			Section {
				Picker("Show command output:", selection: htmlOutputPlacementTagBinding) {
					Text("Below text view").tag(0)
					Text("Right of text view").tag(1)
					Text("New window").tag(2)
				}
			}
		}
		// The other three commit triggers, all measured in the same harness as
		// the keystroke count above. Return is handled by the .onSubmit on each
		// field; this catches the caret leaving one, and a pane switch, which
		// removes this view (Preferences.mm:48 swaps the subview out).
		.onChange(of: focusedPattern) { previous, _ in
			if let previous {
				commitPattern(previous)
			}
		}
		.onDisappear { commitAllPatterns() }
		// Closing the Settings window fires NONE of the above: the window is a
		// shared singleton, so the hosting view is never removed, onDisappear
		// never runs and the focus never moves. Measured: type a pattern, close
		// the window, and every other trigger stays silent -- the edit is lost.
		// Hence willClose, and filtered to our own window, because an
		// unfiltered observer commits a half-typed pattern every time any other
		// window in the app closes, which is the original bug in miniature.
		.background(HostWindowReader { hostWindow = $0 })
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
			if notification.object as AnyObject === hostWindow {
				commitAllPatterns()
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

	private enum PatternField: CaseIterable {
		case exclude, include, binary
	}

	private func patternKey(_ field: PatternField) -> String {
		switch field {
			case .exclude: return TMSettingsExcludeKey()
			case .include: return TMSettingsIncludeKey()
			case .binary:  return TMSettingsBinaryKey()
		}
	}

	private func patternValue(_ field: PatternField) -> String {
		switch field {
			case .exclude: return excludePattern
			case .include: return includePattern
			case .binary:  return binaryPattern
		}
	}

	// TMSettingsSetString skips a value that is already stored, so the
	// deliberately overlapping triggers cost a read rather than a rewrite:
	// tabbing through fields nobody touched writes nothing, and two triggers
	// firing for one edit still write once.
	private func commitPattern(_ field: PatternField) {
		TMSettingsSetString(patternKey(field), patternValue(field))
	}

	private func commitAllPatterns() {
		for field in PatternField.allCases {
			commitPattern(field)
		}
	}
}

// MARK: - Variables pane

// One row of the table. The id is minted when the entry is created and outlives
// every insert and delete above it -- Table's selection and @FocusState both
// key off it, and a row index would not do: deleting row 0 would slide the
// selection and the focus ring onto a different variable instead of moving with
// the one they were on.
struct SettingsVariable: Identifiable {
	let id: Int
	var enabled: Bool
	var name: String
	var value: String
}

// The Variables pane's state. Owned by VariablesPreferences.mm the same way
// SettingsPaneFileBrowserLocation is owned by ProjectsPreferences, and for one
// concrete reason: -commitEditing has to be able to flush a half-typed row from
// Objective-C++, and it cannot reach a value living inside a SwiftUI View.
//
// @MainActor because it drives SwiftUI. Every caller is already main-thread --
// -loadView, -commitEditing, and the view's own callbacks -- unlike
// SettingsPaneUpdateStatus, whose KVO chain is not. Do not relax this to paper
// over a call site that turns out not to be main-thread; the @objc thunk of a
// @MainActor method SIGTRAPs off-main rather than misbehaving quietly.
@objc(SettingsPaneVariables)
@MainActor
public final class SettingsPaneVariables: NSObject, ObservableObject {
	// The defaults array verbatim -- [["enabled": NSNumber, "name": String,
	// "value": String]] -- rather than a parallel Swift model. Every rule that
	// decides what it becomes lives in SettingsVariablesBridge, where
	// Preferences_test can reach it. This class only holds it and decides WHEN
	// to persist.
	@Published private var storage: [[String: Any]] = []
	// Stable ids, one per entry, kept in step with storage by every mutation.
	@Published private var ids: [Int] = []
	@Published var selection: Int?
	private var nextID = 0

	@objc public override init() {
		super.init()
		storage = UserDefaults.standard.array(forKey: kUserDefaultsEnvironmentVariablesKey) as? [[String: Any]] ?? []
		ids = storage.map { _ in mintID() }
	}

	var rows: [SettingsVariable] {
		zip(ids, storage).map { id, entry in
			SettingsVariable(id: id,
			                 enabled: (entry[TMVariableKeyEnabled()] as? NSNumber)?.boolValue ?? false,
			                 name:    entry[TMVariableKeyName()]  as? String ?? "",
			                 value:   entry[TMVariableKeyValue()] as? String ?? "")
		}
	}

	// -1 for "nothing selected", matching NSTableView.selectedRow, which is what
	// the bridge functions expect.
	private var selectedRow: Int {
		guard let selection, let row = ids.firstIndex(of: selection) else { return -1 }
		return row
	}

	private func mintID() -> Int {
		defer { nextID += 1 }
		return nextID
	}

	// Text edits land here per keystroke and stay in memory; -commit persists
	// them. Same split as the Projects pane's pattern fields, for a weaker
	// reason -- NSUserDefaults is atomic and cheap where settings_t::set is a
	// non-atomic rewrite of the user's whole Global.tmProperties -- but the
	// same observable behaviour, which is the point: the AppKit table bound
	// through -tableView:setObjectValue:forTableColumn:row:, which NSTableView
	// calls when editing ENDS, not while it is happening.
	func setValue(_ value: Any, forKey key: String, id: Int) {
		guard let row = ids.firstIndex(of: id) else { return }
		storage = TMVariablesSetValue(storage, row, key, value)
	}

	// The checkbox has no editing session to end, so it persists on the click,
	// exactly as the AppKit cell did.
	func setEnabled(_ enabled: Bool, id: Int) {
		setValue(NSNumber(value: enabled), forKey: TMVariableKeyEnabled(), id: id)
		commit()
	}

	// Returns the new row's id so the caller can put the caret in its name
	// field, which is what -addVariable: did with -editColumn:row:withEvent:select:.
	@discardableResult func add() -> Int {
		let index = TMVariablesInsertionIndex(selectedRow, storage.count)
		storage = TMVariablesInsert(storage, index)
		let id = mintID()
		ids.insert(id, at: index)
		commit()
		selection = id
		return id
	}

	func remove() {
		let row = selectedRow
		guard row != -1 else { return }
		storage = TMVariablesRemove(storage, row)
		ids.remove(at: row)
		commit()
		let next = TMVariablesSelectionAfterRemove(row, storage.count)
		selection = next == -1 ? nil : ids[next]
	}

	// Skips the write when that array is already stored, which is what makes
	// the deliberately overlapping commit triggers free: a pane switch fires
	// both -commitEditing (Preferences.mm:35, before the swap) and .onDisappear
	// (after it), and every needless write posts
	// NSUserDefaultsDidChangeNotification to every @AppStorage in the app.
	@objc public func commit() {
		let stored = UserDefaults.standard.array(forKey: kUserDefaultsEnvironmentVariablesKey) as NSArray?
		guard stored?.isEqual(to: storage) != true else { return }
		UserDefaults.standard.set(storage, forKey: kUserDefaultsEnvironmentVariablesKey)
	}
}

struct VariablesPaneView: View {
	@ObservedObject var model: SettingsPaneVariables
	@FocusState private var focusedCell: Cell?
	@State private var hostWindow: NSWindow?

	private enum Cell: Hashable {
		case name(Int)
		case value(Int)
	}

	var body: some View {
		SettingsPane {
			Section {
				Table(model.rows, selection: $model.selection) {
					// No title and a fixed 16 points, as NSTableColumnNoResizing
					// with matching min and max width gave it.
					TableColumn("") { row in
						Toggle("", isOn: Binding(get: { row.enabled }, set: { model.setEnabled($0, id: row.id) }))
							.labelsHidden()
					}
					.width(16)

					// .plain so a cell looks like a cell until you click into
					// it, the way NSTextFieldCell did. A bordered field per row
					// turns the table into a wall of boxes.
					TableColumn("Variable Name") { row in
						TextField("", text: Binding(get: { row.name }, set: { model.setValue($0, forKey: TMVariableKeyName(), id: row.id) }))
							.textFieldStyle(.plain)
							.focused($focusedCell, equals: .name(row.id))
							.onSubmit { model.commit() }
					}
					.width(min: 60, ideal: 140)

					TableColumn("Value") { row in
						TextField("", text: Binding(get: { row.value }, set: { model.setValue($0, forKey: TMVariableKeyValue(), id: row.id) }))
							.textFieldStyle(.plain)
							.focused($focusedCell, equals: .value(row.id))
							.onSubmit { model.commit() }
					}
					.width(min: 60, ideal: 200)
				}
				// SettingsPane wraps its content in .scrollDisabled(true), and
				// that is an ENVIRONMENT value (EnvironmentValues.isScrollEnabled),
				// so it is inherited by every scrollable descendant -- which is
				// this pane's one real conflict with the shared wrapper, since
				// the other five panes are forms that must NOT scroll inside a
				// fixed-size pane and this one contains a table that must.
				//
				// Measured on this SDK, 2026-08-24, and the result is NOT what
				// the environment value implies: Table ignores it. Hosting the
				// same table three ways -- inheriting the wrapper's disable,
				// overriding it with .scrollDisabled(false), and with no
				// wrapper at all -- produced a byte-identical AppKit hierarchy
				// each time, ListCoreScrollView 460 x 988.5 over a 460 x 960
				// SwiftUIOutlineTableView. The tell is real, not absent: the
				// same probe on a plain ScrollView flips hasVerticalScroller
				// false/true with the modifier, and the Form's OWN
				// HostingScrollView flips with it too. Only the table's does
				// not move.
				//
				// So this line changes nothing today and the table is not
				// clipped either way. Kept because it is one line, it says
				// which behaviour this pane depends on, and the day Table does
				// start reading isScrollEnabled the failure would be a table
				// that silently stops scrolling past its visible rows.
				.scrollDisabled(false)
				// A Table contributes NO intrinsic size in either direction,
				// and PreferencesPane.mm:35 sizes the pane from fittingSize --
				// so without this the pane is whatever the surrounding chrome
				// happens to measure. Measured on this SDK, 2026-08-24: with no
				// frame at all the hosting view fits at 154 x 399, i.e. a
				// 114-point-wide content column holding a table whose own
				// columns already want 402. The height was obvious; the WIDTH
				// is the one that would have shipped, because a too-narrow pane
				// still looks like a pane. These two numbers are chosen to land
				// the whole pane on the 622 x 454 the AppKit view declared.
				.frame(minWidth: 582, minHeight: 372)

				HStack(spacing: 4) {
					Button(action: addVariable) { Image(systemName: "plus") }
						.help("Add variable")
					Button(action: model.remove) { Image(systemName: "minus") }
						.help("Remove variable")
						// The old pane bound the remove button's enabled state
						// to a canRemove property that was true only with a row
						// selected.
						.disabled(model.selection == nil)
					Spacer()
				}
			}
		}
		// The same four commit triggers as the Projects pane's pattern fields,
		// for the same reasons: .onSubmit on each field is Return, this catches
		// the caret leaving a cell, .onDisappear catches a pane switch
		// (Preferences.mm:48 swaps the subview out) and willClose catches the
		// window being closed with the caret still in a field -- which fires
		// none of the others, because the Settings window is a shared singleton
		// whose hosting view is never removed. VariablesPreferences
		// -commitEditing is a fifth, and the only one that runs BEFORE a pane
		// switch is allowed to proceed.
		.onChange(of: focusedCell) { previous, _ in
			if previous != nil {
				model.commit()
			}
		}
		.onDisappear { model.commit() }
		.background(HostWindowReader { hostWindow = $0 })
		.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
			if notification.object as AnyObject === hostWindow {
				model.commit()
			}
		}
	}

	private func addVariable() {
		let id = model.add()
		// The new row does not exist in the Table until SwiftUI has run an
		// update pass, and focus assigned before that is dropped on the floor.
		Task { @MainActor in focusedCell = .name(id) }
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
	@MainActor
	@objc public static func variablesView(variables: SettingsPaneVariables) -> NSView {
		let view = NSHostingView(rootView: VariablesPaneView(model: variables))
		// Same fittingSize discipline as the two panes above, but load-bearing
		// in a way they are not: a Table contributes no intrinsic height, so
		// this measures the .frame(minHeight:) the view declares. Drop that and
		// this is the 0x0 that PreferencesPane.mm:35 pins the pane to.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
