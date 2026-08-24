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
	// What is in NSUserDefaults, as this pane last saw it. Two jobs: it is the
	// baseline the re-enable rule compares against, and it is what -persist
	// compares against so a pane that was merely VISITED writes nothing at all.
	private var committed: [[String: Any]] = []

	@objc public override init() {
		super.init()
		storage = Self.load()
		committed = storage
		ids = storage.map { _ in mintID() }
	}

	// `as? [[String: Any]] ?? []` was wrong in a way that ate data: a value of
	// the wrong shape -- a dictionary, or an array with one non-dictionary
	// element -- failed the whole cast, and .onDisappear then wrote the empty
	// result back. Opening the pane and leaving destroyed the key.
	//
	// Two halves fix it and both are needed. Here: fall back to element-wise
	// parsing so a single bad entry costs that entry rather than the array. In
	// -persist: write only when this pane actually changed something, so
	// whatever could not be parsed stays on disk untouched until the user
	// edits, which is what the AppKit pane did -- it only ever wrote from
	// -tableView:setObjectValue: and the two buttons.
	private static func load() -> [[String: Any]] {
		let raw = UserDefaults.standard.object(forKey: kUserDefaultsEnvironmentVariablesKey)
		if let entries = raw as? [[String: Any]] { return entries }
		return (raw as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
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
	//
	// Deliberately does NOT apply the re-enable rule; -commit does. See
	// TMVariablesEnableEdited's header comment for why that split matters.
	func setValue(_ value: Any, forKey key: String, id: Int) {
		guard let row = ids.firstIndex(of: id) else { return }
		storage = TMVariablesSetValue(storage, row, key, value)
	}

	// Escape. AppKit's field editor aborted the edit and left the row alone;
	// SwiftUI's TextField has already written the binding by the time
	// .onExitCommand runs, so the pane has to put the row back itself.
	//
	// Measured on this SDK: reverting and dropping focus in the same turn does
	// NOT work -- ending the editing session makes TextField write the field
	// editor's text back over the revert. Reverting and leaving focus where it
	// is does, and the field editor redraws with the restored text.
	func revert(id: Int) {
		guard let row = ids.firstIndex(of: id) else { return }
		storage = TMVariablesRevert(storage, committed, row)
	}

	// The checkbox has no editing session to end, so it persists on the click,
	// exactly as the AppKit cell did. Through -commit rather than -persist so a
	// half-typed row elsewhere in the table is not written past its rule: the
	// rule keys off name and value, so it cannot undo the click itself.
	func setEnabled(_ enabled: Bool, id: Int) {
		setValue(NSNumber(value: enabled), forKey: TMVariableKeyEnabled(), id: id)
		commit()
	}

	// Returns the new row's id so the caller can put the caret in its name
	// field, which is what -addVariable: did with -editColumn:row:withEvent:select:.
	//
	// -commit BEFORE the insert, -persist after: the re-enable rule compares
	// row for row and cannot do that across a count change, so pending edits
	// are flushed while the counts still match.
	@discardableResult func add() -> Int {
		commit()
		let index = TMVariablesInsertionIndex(selectedRow, storage.count)
		storage = TMVariablesInsert(storage, index)
		let id = mintID()
		ids.insert(id, at: index)
		persist()
		selection = id
		return id
	}

	// The old pane also called -scrollRowToVisible: on the re-selected row.
	// There is no supported way to do that here, measured rather than assumed;
	// see the note above `body`.
	func remove() {
		let row = selectedRow
		guard row != -1 else { return }
		commit()
		storage = TMVariablesRemove(storage, row)
		ids.remove(at: row)
		persist()
		let next = TMVariablesSelectionAfterRemove(row, storage.count)
		selection = next == -1 ? nil : ids[next]
	}

	// End of an editing session: apply the re-enable rule against what was last
	// committed, then write. Every trigger the view has -- Return, focus
	// leaving a cell, .onDisappear, willClose -- and -commitEditing come here.
	@objc public func commit() {
		storage = TMVariablesEnableEdited(committed, storage)
		persist()
	}

	// Compares against `committed` rather than re-reading NSUserDefaults, which
	// is what stops a merely-visited pane writing: at load the two are equal by
	// construction even when the stored value was malformed and -load could
	// only salvage part of it. It also keeps the deliberately overlapping
	// commit triggers free -- a pane switch fires both -commitEditing
	// (Preferences.mm:35, before the swap) and .onDisappear (after it), and
	// every needless write posts NSUserDefaultsDidChangeNotification to every
	// @AppStorage in the app.
	private func persist() {
		guard !(committed as NSArray).isEqual(to: storage) else { return }
		UserDefaults.standard.set(storage, forKey: kUserDefaultsEnvironmentVariablesKey)
		committed = storage
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

	// NOT scrolling the re-selected row into view after a delete, the way
	// -delete: did with -scrollRowToVisible:, is a known and deliberate gap.
	// Measured on this SDK, 2026-08-24: ScrollViewReader's proxy.scrollTo(id)
	// drives a Table when the table is NOT inside a Form -- clip origin -28 ->
	// 497 over a 960-point document -- and is a silent no-op in all four
	// placements inside one (wrapping the Section's contents, wrapping the
	// framed table, inside the frame, and hiding the reader in a VStack). Every
	// one of those also costs 20 points of pane width, because a grouped Form
	// stops insetting a Section child that is a ScrollViewReader: 622 -> 642.
	// .scrollPosition(id:) is layout-neutral and does not move a Table at all.
	// -scrollRowToVisible: and -scrollToVisible: on the SwiftUIOutlineTableView
	// found by walking the AppKit tree are no-ops too; only driving its clip
	// view by hand works, which means reimplementing AppKit's clamping against
	// a private view. Not worth it for a row the user just clicked and which is
	// therefore on screen already.
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
							.onExitCommand { model.revert(id: row.id) }
					}
					.width(min: 60, ideal: 140)

					TableColumn("Value") { row in
						TextField("", text: Binding(get: { row.value }, set: { model.setValue($0, forKey: TMVariableKeyValue(), id: row.id) }))
							.textFieldStyle(.plain)
							.focused($focusedCell, equals: .value(row.id))
							.onSubmit { model.commit() }
							.onExitCommand { model.revert(id: row.id) }
					}
					.width(min: 60, ideal: 200)
				}
				// SettingsPane wraps its content in .scrollDisabled(true),
				// and that is an ENVIRONMENT value
				// (EnvironmentValues.isScrollEnabled), inherited by every
				// scrollable descendant. Measured on this SDK, 2026-08-24:
				// Table does not read it -- the same table inheriting the
				// disable, overriding it here, and with no wrapper at all
				// built an identical AppKit hierarchy every time. The probe
				// is not blind; a plain ScrollView flips hasVerticalScroller
				// with the modifier and so does the Form's own
				// HostingScrollView.
				//
				// So this line changes nothing today. Kept because it is one
				// line and it names the behaviour this pane depends on: the
				// day Table starts reading isScrollEnabled, the failure would
				// be a table that silently stops scrolling past its visible
				// rows. It is NOT what keeps the pane a fixed height -- the
				// exact frame below is, and the Form's own scroller staying
				// disabled is right, because a pane that never overflows has
				// nothing to scroll.
				.scrollDisabled(false)
				// EXACT, not minimum. A Table lays out at full content
				// height and contributes no intrinsic size in either
				// direction, so with .frame(minHeight:) the pane's
				// fittingSize tracked the row count -- measured 622 x 454 at
				// 9 rows, 622 x 474 at 15, 622 x 594 at 20, 622 x 1074 at 40
				// -- and OakTransitionViewController.mm:72-74 sizes the
				// WINDOW to that, clamped to the screen at :77-85. Past
				// ~20 variables on a laptop the + and - buttons clipped off
				// the bottom with nothing scrolling to reach them:
				// default_environment() (Keys.mm:6) already ships 9.
				//
				// Pinned, the table's own ListCoreScrollView becomes 582 x
				// 372 over its full-height document and scrolls internally,
				// which is what NSScrollView.hasVerticalScroller = YES gave
				// the AppKit pane at a fixed NSMakeRect(0, 0, 622, 454).
				//
				// The width matters as much and for a different reason: with
				// no frame at all the hosting view fits at 154 x 399, a
				// 114-point content column holding a table whose columns want
				// 402, and a too-narrow pane still looks like a pane.
				.frame(width: 582, height: 372)

				HStack(spacing: 4) {
					Button(action: addVariable) { Image(systemName: "plus") }
						.help("Add variable")
					Button(action: { model.remove() }) { Image(systemName: "minus") }
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
		// A pane is sized from its fittingSize and then pinned to that:
		// OakTransitionViewController.mm:42 falls back to it for a zero frame,
		// and :72-74 sizes the window from the frame. (PreferencesPane.mm is a
		// grid-view helper and has nothing to do with it.) A 0x0 here is what
		// made the Terminal pane look like a dead click for months. status is
		// seeded by the caller before this runs, so this measures real text,
		// not "".
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
		// this measures the exact .frame(width:height:) the view declares --
		// and, because that frame is exact rather than a minimum, it is the
		// same number at any row count. Drop the frame and this is the 0x0 that
		// OakTransitionViewController.mm:42 pins the pane to.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
