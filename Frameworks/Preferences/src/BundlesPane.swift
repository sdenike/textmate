// Frameworks/Preferences/src/BundlesPane.swift
import Foundation
import SwiftUI

// MARK: - Model

// Pushed from BundlesPreferences the same way SettingsPaneMateInstall is:
// ObjC++ owns the real state (BundlesManager.sharedInstance.bundles, the
// category set, the reset-dismissed enablement rule) and calls -update
// whenever any of it changes -- initial load, a KVO-observed change to
// BundlesManager's "bundles", and after every action below completes.
// @MainActor because it drives SwiftUI, and every caller is already
// main-thread: BundlesManager's own completion blocks all dispatch back to
// the main queue (BundlesManager.h's doc comments on each of them).
@objc(SettingsPaneBundles)
@MainActor
public final class SettingsPaneBundles: NSObject, ObservableObject {
	@Published var rows: [TMBundleRow] = []
	@Published var categories: [String] = []
	@Published var resetDismissedEnabled: Bool = false

	@objc public override init() {
		super.init()
	}

	@objc public func update(rows: [TMBundleRow], categories: [String], resetDismissedEnabled: Bool) {
		self.rows = rows
		self.categories = categories
		self.resetDismissedEnabled = resetDismissedEnabled
	}
}

// MARK: - Row

// A plain Swift value wrapping TMBundleRow for the Table: KeyPathComparator
// needs Sendable, Comparable-keyed properties to sort by, which a struct gives
// for free and an NSObject mirror does not need to worry about providing.
// `source` keeps the real TMBundleRow so the gear menu can still call
// TMBundleMenuEnablementForRow -- the tested enablement rule -- rather than
// re-deriving it here.
struct BundleRow: Identifiable {
	let source: TMBundleRow

	var id: String { source.identifier }
	var name: String { source.name }
	var category: String? { source.category }
	var webLinkURLString: String? { source.webLinkURLString }
	var updated: Date? { source.updated }
	var textSummary: String { source.textSummary }
	var installState: TMBundleInstallState { source.installState }
	var installedToggleEnabled: Bool { source.installedToggleEnabled }
	var autoUpdateEnabled: Bool { source.autoUpdateEnabled }
	var ref: String? { source.ref }
	var downloadURLString: String? { source.downloadURLString }
	var path: String? { source.path }

	// NSSortDescriptor used localizedCompare: for name/textSummary; Swift's
	// String is only lexicographically Comparable via <, which would sort
	// "Zebra" before "able". Lowercasing first is a disclosed approximation --
	// no real collation -- close enough for a bundle name/description list and
	// far cheaper than hand-rolling a SortComparator around
	// String.localizedCompare.
	var sortName: String { name.localizedLowercase }
	var sortSummary: String { textSummary.localizedLowercase }
	var sortInstalled: Int { source.isInstalled ? 1 : 0 }

	init(_ row: TMBundleRow) {
		source = row
	}
}

// MARK: - Category scope bar

// OakScopeBarView's single-select-with-empty behaviour, reimplemented directly
// rather than hosted: nothing else in this pane wires updateGoToMenu: or
// selectNextButton:/selectPreviousButton: the way Favorites.mm and the filter
// choosers do, so hosting the AppKit control would buy nothing here that a
// plain button row does not.
private struct CategoryScopeBar: View {
	let categories: [String]
	@Binding var selected: String?

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 4) {
				ForEach(categories, id: \.self) { category in
					if selected == category {
						Button(category) { selected = nil }
							.buttonStyle(.borderedProminent)
							.controlSize(.small)
					} else {
						Button(category) { selected = category }
							.buttonStyle(.bordered)
							.controlSize(.small)
					}
				}
			}
		}
	}
}

// MARK: - Data-entry sheets

// The three sheets CLAUDE.md calls the "dated part" of the AppKit pane: an
// NSAlert with a hand-built NSView accessoryView. Rebuilt here as plain
// SwiftUI forms; the Remove confirmation and error alerts stay NSAlert in
// BundlesPreferences.mm, which is where the task says system-standard alerts
// belong.

private struct AddBundleSheet: View {
	@Environment(\.dismiss) private var dismiss
	@State private var url = ""
	@State private var ref = ""
	let onAdd: (String, String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Add Bundle from URL").font(.headline)
			Text("Enter the GitHub URL for a TextMate bundle and the branch, tag, or commit to track. The bundle will be fetched and installed immediately.")
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			LabeledContent("URL:") {
				TextField("https://github.com/owner/repo.tmbundle", text: $url)
			}
			LabeledContent("Ref:") {
				TextField("main", text: $ref)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Add") {
					let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !trimmedURL.isEmpty else { return }
					onAdd(trimmedURL, ref.trimmingCharacters(in: .whitespacesAndNewlines))
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(width: 380)
	}
}

private struct ChangeRefSheet: View {
	@Environment(\.dismiss) private var dismiss
	@State var ref: String
	let bundleName: String
	let onUpdate: (String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Change Ref for \u{201C}\(bundleName)\u{201D}").font(.headline)
			Text("Enter a branch, tag, or 40-character commit SHA. The bundle will be re-fetched at the new ref.")
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			TextField("main", text: $ref)
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Update") {
					let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !trimmed.isEmpty else { return }
					onUpdate(trimmed)
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(width: 360)
	}
}

private struct EditBundleSheet: View {
	@Environment(\.dismiss) private var dismiss
	@State var url: String
	@State var ref: String
	let bundleName: String
	let onSave: (String, String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Edit Bundle \u{201C}\(bundleName)\u{201D}").font(.headline)
			Text("Change the URL or ref. Changing the URL re-fetches the bundle; the UUID in the fetched info.plist must match. Name is derived from info.plist and cannot be edited here.")
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
			LabeledContent("URL:") {
				TextField("", text: $url)
			}
			LabeledContent("Ref:") {
				TextField("main", text: $ref)
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
				Button("Save") {
					let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !trimmedURL.isEmpty else { return }
					onSave(trimmedURL, ref.trimmingCharacters(in: .whitespacesAndNewlines))
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding()
		.frame(width: 380)
	}
}

// MARK: - Footer host

// The footer is built and bound in BundlesPreferences.mm -- divider, spinner
// and status text wrapped in OakWrapInGlass, bound with live Cocoa bindings to
// BundleInstallHelper.sharedInstance -- and merely HOSTED here, the same
// division TerminalPane.swift's HelpButtonHost draws around the help button.
// CLAUDE.md's Liquid Glass section is explicit that a glass backdrop with no
// content collapses to 0x0 and that OakWrapInGlass's return value, not the bar
// passed in, is where content belongs; BundlesPreferences.mm follows both
// rules, so this only has to host the finished view, not rebuild it.
private struct FooterHost: NSViewRepresentable {
	let view: NSView

	func makeNSView(context: Context) -> NSView { view }
	func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Bundles pane

struct BundlesPaneView: View {
	@ObservedObject var model: SettingsPaneBundles
	let footer: NSView

	let onToggleInstalled: (String) -> Void
	let onAddBundle: (String, String) -> Void
	let onToggleAutoUpdate: (String) -> Void
	let onChangeRef: (String, String) -> Void
	let onEditBundle: (String, String, String) -> Void
	let onUninstall: (String) -> Void
	let onRemove: (String) -> Void
	let onRevert: (String) -> Void
	let onCheckForUpdatesNow: () -> Void
	let onResetDismissedSuggestions: () -> Void

	// Plain NSUserDefaults-backed, exactly like the Projects pane's un-wrapped
	// @AppStorage fields -- nothing here needs transforming except the
	// negation. kUserDefaultsDisableBundleUpdatesKey's real consumer is
	// BundlesManager.mm:85 (`self.autoUpdateBundles = ![...] boolForKey:...]`);
	// kUserDefaultsDisableBundleSuggestionsKey's is
	// DocumentWindowController.mm:1185. Both read the key un-negated, so the
	// positively-phrased checkbox must write the negation, same as the
	// Terminal pane's rmate checkbox.
	@AppStorage(kUserDefaultsDisableBundleUpdatesKey)     private var disableBundleUpdates = false
	@AppStorage(kUserDefaultsDisableBundleSuggestionsKey) private var disableBundleSuggestions = false

	@State private var searchText = ""
	@State private var selectedCategory: String?
	@State private var selection: String?
	@State private var sortOrder = [
		KeyPathComparator(\BundleRow.sortName, order: .forward),
		KeyPathComparator(\BundleRow.sortInstalled, order: .forward),
		KeyPathComparator(\BundleRow.updated, order: .forward),
		KeyPathComparator(\BundleRow.sortSummary, order: .forward),
	]

	@State private var showingAddSheet = false
	@State private var changeRefTarget: BundleRow?
	@State private var editTarget: BundleRow?

	private static let updatedFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter
	}()

	// filterStringDidChange:'s NSCompoundPredicate, then didClickTableColumn:'s
	// sortDescriptors -- ported as TMBundlesFilterRows (tested,
	// t_settings_bundles.mm) followed by Table's own native sort, rather than
	// hand-porting the NSSortDescriptor-cycling algorithm.
	private var visibleRows: [BundleRow] {
		TMBundlesFilterRows(model.rows, searchText, selectedCategory).map(BundleRow.init).sorted(using: sortOrder)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			SettingsPane {
				Section {
					HStack {
						// maxWidth so a category list long enough to need it
						// scrolls instead of stretching the row -- exactly the
						// behaviour a scope bar is for. Does NOT explain the
						// pane's 622 -> 642 width; see the note on the whole
						// row's .frame below, established by bisection to be
						// unrelated to this view's own content.
						CategoryScopeBar(categories: model.categories, selected: $selectedCategory)
							.frame(maxWidth: 300, alignment: .leading)
						Spacer()
						searchField
					}
					// 582, matching the table below, but the pane still comes
					// out 642 wide rather than Variables' 622 -- bisected down
					// to "this Section has a second row at all", reproducible
					// even with the row's content replaced by a bare Text("x")
					// and with CategoryScopeBar/searchField both removed. That
					// is the same 20-point jump CLAUDE.md already documents
					// for the Variables pane ("a grouped Form stops insetting
					// a Section child that is a ScrollViewReader: 622 -> 642")
					// -- a second row changes how .formStyle(.grouped) insets
					// the Section, not anything this row draws. Fighting it
					// further did not move the number; accepted as a known
					// SwiftUI Form quirk in this exact codebase rather than
					// chased into the framework's own layout internals.
					.frame(width: 582, alignment: .leading)

					Table(visibleRows, selection: $selection, sortOrder: $sortOrder) {
						TableColumn("", sortUsing: KeyPathComparator(\BundleRow.sortInstalled)) { row in
							installedCell(row)
						}
						.width(16)

						TableColumn("Bundle", sortUsing: KeyPathComparator(\BundleRow.sortName)) { row in
							Text(row.name).lineLimit(1).contextMenu { rowMenuContent(row) }
						}
						.width(min: 100, ideal: 140)

						TableColumn("") { row in
							webLinkCell(row)
						}
						.width(16)

						TableColumn("Updated", sortUsing: KeyPathComparator(\BundleRow.updated)) { row in
							Text(row.updated.map { Self.updatedFormatter.string(from: $0) } ?? "")
								.frame(maxWidth: .infinity, alignment: .trailing)
								.contextMenu { rowMenuContent(row) }
						}
						.width(90)

						TableColumn("Description", sortUsing: KeyPathComparator(\BundleRow.sortSummary)) { row in
							Text(row.textSummary).lineLimit(1).truncationMode(.tail).contextMenu { rowMenuContent(row) }
						}
						.width(min: 100, ideal: 140)

						TableColumn("") { row in
							gearCell(row)
						}
						.width(22)
					}
					// EXACT, not minimum -- a Table contributes no intrinsic
					// size in either direction (CLAUDE.md, the Variables
					// pane's fittingSize trap), so this is what keeps
					// OakTransitionViewController.mm:42's pane size constant
					// regardless of how many bundles are installed. See
					// BundlesPane's factory method for the measured numbers.
					.frame(width: 582, height: 300)

					// EXACT width on both rows below, same reason and same
					// number as the table above: an unconstrained HStack's
					// ideal width is the sum of its children's ideal widths,
					// and "Suggest bundle installs for unrecognized file
					// types" alongside "Reset Dismissed Bundle Suggestions"
					// measured wider than a Spacer() shrinks to (744 total
					// pane width, not the 622 every other pane settled on).
					// Pinning the row lets the checkbox label wrap instead of
					// dictating the Form's own ideal width.
					HStack {
						Button("+ Add Bundle\u{2026}") { showingAddSheet = true }
						Button("Check Now", action: onCheckForUpdatesNow)
						Spacer()
						Toggle("Check for and install updates automatically", isOn: checkForUpdatesBinding)
					}
					.frame(width: 582, alignment: .leading)

					HStack {
						Button("Reset Dismissed Bundle Suggestions", action: onResetDismissedSuggestions)
							.disabled(!model.resetDismissedEnabled)
						Spacer()
						Toggle("Suggest bundle installs for unrecognized file types", isOn: suggestBundlesBinding)
					}
					.frame(width: 582, alignment: .leading)
				}
			}

			// maxWidth: .infinity rather than TerminalPaneView's .fixedSize():
			// the footer's divider is pinned edge-to-edge inside the AppKit
			// view BundlesPreferences builds (H:|[divider]|), so it needs the
			// full proposed pane width, not its own minimal ideal width -- the
			// help button being hosted stretches to nothing, one plain button.
			// Height is left alone, so the row still reports its own natural
			// height rather than stretching to fill the VStack.
			FooterHost(view: footer)
				.frame(maxWidth: .infinity)
		}
		.sheet(isPresented: $showingAddSheet) {
			AddBundleSheet(onAdd: onAddBundle)
		}
		.sheet(item: $changeRefTarget) { target in
			ChangeRefSheet(ref: target.ref ?? "", bundleName: target.name) { ref in
				onChangeRef(target.id, ref)
			}
		}
		.sheet(item: $editTarget) { target in
			EditBundleSheet(url: target.downloadURLString ?? "", ref: target.ref ?? "", bundleName: target.name) { url, ref in
				onEditBundle(target.id, url, ref)
			}
		}
	}

	private var searchField: some View {
		HStack(spacing: 4) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.secondary)
				.font(.system(size: 11))
			TextField("", text: $searchText)
				.textFieldStyle(.plain)
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 3)
		.background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
		.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
		.frame(width: 120)
		.controlSize(.small)
	}

	// Mixed means an install or uninstall is in flight for this bundle
	// (BundleInstallHelper.bundlesBeingInstalled) -- shown as a spinner rather
	// than the AppKit checkbox's mixed-state dash, which reads more plainly as
	// "in progress" than a third checkbox state does.
	@ViewBuilder
	private func installedCell (_ row: BundleRow) -> some View {
		switch row.installState {
			case .mixed:
				ProgressView()
					.controlSize(.small)
					.scaleEffect(0.6)
					.frame(width: 16, height: 16)
			default:
				Toggle("", isOn: Binding(
					get: { row.installState == .on },
					set: { _ in onToggleInstalled(row.id) }
				))
				.labelsHidden()
				.toggleStyle(.checkbox)
				.controlSize(.small)
				.disabled(!row.installedToggleEnabled)
		}
	}

	@ViewBuilder
	private func webLinkCell (_ row: BundleRow) -> some View {
		if let string = row.webLinkURLString, let url = URL(string: string) {
			Button {
				NSWorkspace.shared.open(url)
			} label: {
				Image(systemName: "link")
			}
			.buttonStyle(.borderless)
			.controlSize(.small)
			.contextMenu { rowMenuContent(row) }
		} else {
			Color.clear.frame(width: 16, height: 16).contextMenu { rowMenuContent(row) }
		}
	}

	@ViewBuilder
	private func gearCell (_ row: BundleRow) -> some View {
		Menu {
			rowMenuContent(row)
		} label: {
			Image(systemName: "gearshape")
		}
		.menuStyle(.borderlessButton)
		.frame(width: 22)
	}

	// -populateMenu:forBundle:, ported item for item including order: Auto
	// Update, a separator, Change Ref.../Edit Bundle..., a separator,
	// Uninstall/Remove Bundle.../Revert to Default, a separator, Copy
	// URL/Reveal in Finder. Shared between the gear button and every column's
	// .contextMenu so right-clicking anywhere in the row shows the same menu,
	// matching -menuNeedsUpdate: reading aTableView.clickedRow rather than the
	// selection.
	@ViewBuilder
	private func rowMenuContent (_ row: BundleRow) -> some View {
		// TMBundleMenuEnablement's fields are plain C `BOOL`: Swift imports a
		// BOOL struct FIELD as ObjCBool, not Bool -- unlike a BOOL property or
		// method, which gets the usual automatic bridging. .boolValue is the
		// standard unwrap.
		let enablement = TMBundleMenuEnablementForRow(row.source)

		Toggle("Auto Update", isOn: Binding(
			get: { row.autoUpdateEnabled },
			set: { _ in onToggleAutoUpdate(row.id) }
		))
		.disabled(!enablement.autoUpdateEnabled.boolValue)

		Divider()

		Button("Change Ref\u{2026}") { changeRefTarget = row }
			.disabled(!enablement.changeRefEnabled.boolValue)
		Button("Edit Bundle\u{2026}") { editTarget = row }
			.disabled(!enablement.editEnabled.boolValue)

		Divider()

		Button("Uninstall") { onUninstall(row.id) }
			.disabled(!enablement.uninstallEnabled.boolValue)
		Button("Remove Bundle\u{2026}") { onRemove(row.id) }
			.disabled(!enablement.removeEnabled.boolValue)
		Button("Revert to Default") { onRevert(row.id) }
			.disabled(!enablement.revertEnabled.boolValue)

		Divider()

		Button("Copy URL") {
			NSPasteboard.general.clearContents()
			if let string = row.downloadURLString {
				NSPasteboard.general.setString(string, forType: .string)
			}
		}
		.disabled(!enablement.copyURLEnabled.boolValue)

		Button("Reveal in Finder") {
			if let path = row.path {
				NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
			}
		}
		.disabled(!enablement.revealEnabled.boolValue)
	}

	private var checkForUpdatesBinding: Binding<Bool> {
		Binding(get: { !disableBundleUpdates }, set: { disableBundleUpdates = !$0 })
	}

	private var suggestBundlesBinding: Binding<Bool> {
		Binding(get: { !disableBundleSuggestions }, set: { disableBundleSuggestions = !$0 })
	}
}

extension SettingsPaneFactory {
	@MainActor
	@objc public static func bundlesView(
		model: SettingsPaneBundles,
		footer: NSView,
		onToggleInstalled: @escaping (String) -> Void,
		onAddBundle: @escaping (String, String) -> Void,
		onToggleAutoUpdate: @escaping (String) -> Void,
		onChangeRef: @escaping (String, String) -> Void,
		onEditBundle: @escaping (String, String, String) -> Void,
		onUninstall: @escaping (String) -> Void,
		onRemove: @escaping (String) -> Void,
		onRevert: @escaping (String) -> Void,
		onCheckForUpdatesNow: @escaping () -> Void,
		onResetDismissedSuggestions: @escaping () -> Void
	) -> NSView {
		let view = NSHostingView(rootView: BundlesPaneView(
			model: model,
			footer: footer,
			onToggleInstalled: onToggleInstalled,
			onAddBundle: onAddBundle,
			onToggleAutoUpdate: onToggleAutoUpdate,
			onChangeRef: onChangeRef,
			onEditBundle: onEditBundle,
			onUninstall: onUninstall,
			onRemove: onRemove,
			onRevert: onRevert,
			onCheckForUpdatesNow: onCheckForUpdatesNow,
			onResetDismissedSuggestions: onResetDismissedSuggestions
		))
		// Same fittingSize discipline as every other pane: OakTransitionViewController.mm:42
		// pins the pane to this. model and footer are both seeded by the caller
		// (BundlesPreferences -loadView) before this runs, so this measures the
		// real row count and a real, already-bound footer, not empty ones.
		// Measured 2026-08-27 with a standalone probe linked against a real
		// build: 642 x 479 at 0, 1, 9, 54 and 200 rows -- identical every time,
		// which is what the two EXACT .frame(width:582, ...) rows in
		// BundlesPaneView buy. 642 rather than the other panes' 622 is a known
		// SwiftUI Form quirk, not a bundle-count dependency; see the comment on
		// the scope bar/search row's own .frame.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
