// Frameworks/Preferences/src/SettingsSupport.swift
import Foundation

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

import SwiftUI

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
// it is only ever touched from KVO callbacks that fire on the main thread --
// every mutation of checking/errorString in SoftwareUpdate.mm either runs on
// the main thread already (the synchronous self.checking = YES at the start of
// a check) or is dispatched back to it (the async completion handler).
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
}
