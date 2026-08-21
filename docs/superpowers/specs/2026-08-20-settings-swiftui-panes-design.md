# Settings panes as SwiftUI islands — design

Date: 2026-08-20
Status: approved, not yet implemented
Phase: 6 (SwiftUI islands) — the second island, after onboarding

## Why

Settings is 2,544 lines across 18 files, and the parts that hurt are the panes rather than the
window. Four of the six bind through `NSUserDefaultsController` and value transformers, so a negated
checkbox is invisible unless you notice `NSNegateBooleanTransformerName` in the binding call. One
pane loads from a xib — and twelve xibs in this repository silently failed to ship for months,
including that one, because `assemble_resources.sh` globbed only three image extensions. The window
itself is 234 lines that work.

The goal the maintainer stated is a uniform, modern look fitting macOS 26. That argues for replacing
pane *contents*, defining the styling once, and leaving the shell alone.

## Scope

**In scope.** Porting preference pane contents to SwiftUI, hosted inside the existing AppKit shell;
a shared style layer so "uniform" is defined in one place; making the defaults keys reachable from
Swift.

**Out of scope, deliberately.**

- **The window shell.** `Preferences.mm` keeps the window, toolbar, ⌘1–⌘9 pane switching,
  `OakTransitionViewController`, and window/pane persistence. It works, it is not where the cost is,
  and replacing it would put every pane behind one enormous parity check.
- **`BundlesPreferences` (903 lines).** It is not a preferences pane. It is a bundle manager with an
  `NSArrayController`-backed table, network installs, four modal sheets, and an eight-item contextual
  menu — larger than the entire Setup Assistant. It gets its own decision after the simple panes
  land, and staying in AppKit is a legitimate outcome.
- **`TerminalPreferences` (372 lines).** Privileged `mate` installation through Authorization
  Services, plus the only xib. Sequenced last for the same reason the Setup Assistant cut its `mate`
  step: a second route to a privileged filesystem write earns its risk only once the pattern is
  proven.
- **The `settings_t` bridge and a SwiftUI encoding picker.** Both are needed by `FilesPreferences`
  and neither should ride along with the pane that establishes the pattern. See "Why not Files
  first".
- **About.** Evaluated 2026-08-19 and dropped — it is a `WKWebView`, not AppKit. See `HANDOFF.md`.

## Decisions

| Decision | Rationale |
|---|---|
| Keep the AppKit shell | 234 working lines; the panes are the cost |
| Modern `Form` styling, not visual parity | The maintainer's stated goal is a uniform, modern look |
| Hold all panes on one branch, ship together | Settings never reaches users half-modern and half-old |
| `SoftwareUpdatePreferences` first | Pure defaults, three controls, no custom controls, no C++ |

## Why not Files first

Files looked like the obvious starting point at 145 lines, and reading it changed that.
`FilesPreferences` writes to **two** systems: its checkboxes go to `NSUserDefaults`, but file types,
encoding and line endings go through `settings_t::set` — TextMate's own C++ settings layer, which
cannot cross a bridging header. It also uses `OakEncodingPopUpButton`, a custom control backed by
`Charsets.plist`.

So Files needs a host-mediated bridge *and* a reimplemented encoding picker: the two hardest pieces
of this whole effort, on the pane whose job is to prove the easy case works. `SoftwareUpdate` has
three controls, all plain `NSUserDefaults`, and its only unusual behaviour — a 60-second timer
refreshing a relative date — is something SwiftUI expresses more cleanly than AppKit does.

## Architecture

### Where the Swift lives

`Preferences` is `type: library.static`, the same shape as `SetupAssistantCore`. But **no framework
target in this repository has ever contained Swift** — only the `TextMate` app target does. This
adds the second, with its own bridging header, and that is the genuinely new mechanism here. It gets
proven on its own before a pane depends on it, exactly as the first `.swift` file did.

### How a SwiftUI pane satisfies the shell

`PreferencesPane.h` declares `OakSetupGridViewWithSeparators (NSGridView*, std::vector<NSUInteger>)`.
It contains C++, so it can never be imported by a bridging header, and the pane contract therefore
stays on the Objective-C++ side.

Each pane remains a `PreferencesPane` subclass. Its `loadView` installs an `NSHostingView` wrapping
the SwiftUI content instead of hand-building AppKit controls. The shell — toolbar, transitions,
persistence, ⌘1–⌘9 — never learns that anything changed.

### How Swift reaches the defaults

`Keys.h` is pure Objective-C: it declares every key as `extern NSString* const` and contains no C++
whatsoever. It is one line short of being bridgeable — it currently relies on the prefix header for
`NSString`, so it needs its own `#import <Foundation/Foundation.h>`. With that, the bridging header
can import it and Swift uses `@AppStorage` against the **real** constants.

This is worth the one-line change rather than retyping key names in Swift. Retyped literals are
exactly what produced this session's `didPromptForDefaultBundles` / `DidPromptForDefaultBundles`
bug: a test that passed while proving nothing, because `NSUserDefaults` keys are case-sensitive and
nothing compared the literal against the real constant. Six panes of retyped keys would be six
chances to repeat it.

### Value transformers become explicit

`NSNegateBooleanTransformerName` and the custom channel and line-ending transformers disappear into
computed `Binding`s in Swift. This is a readability gain as much as a mechanical one: today a
checkbox whose meaning is inverted looks identical in source to one that is not, and the difference
lives in a transformer name inside a `bind:toObject:withKeyPath:options:` call.

### The shared style layer

A `SettingsForm` layer wrapping `Form` with `.formStyle(.grouped)` plus this app's spacing and
section conventions. Panes declare *what* they configure; none of them decides how it looks. Six
panes each making their own layout choices is precisely how a window ends up looking inconsistent,
which is the outcome this work exists to prevent.

## Sequencing

| Order | Pane | Lines | Why here |
|---|---|---|---|
| 1 | SoftwareUpdate | 154 | Pure defaults; proves the target, bridging, hosting and style layer |
| 2 | Projects | 205 | Popups and an open panel; still plain defaults |
| 3 | Variables | 189 | An editable table — first real collection editing |
| 4 | Files | 145 | Needs the `settings_t` bridge and an encoding picker |
| 5 | Terminal | 372 | Privileged install, and the xib goes away with it |
| 6 | Bundles | 903 | Its own decision; AppKit is a legitimate outcome |

Each pane after the first is a bounded change with a short design in chat, not its own spec. Only the
first establishes anything.

## The gate

The design spec's Phase 6 gate reads *"visual parity pass, no regressions in the responder chain or
key equivalents."* The parity half is deliberately abandoned here — the panes are **meant** to look
different. It is replaced by behaviour:

- **Every control reads and writes the same defaults key with the same semantics.** Verified
  mechanically: `defaults export com.shelbydenike.TextMate before.plist`, toggle every control in
  the pane, export again, diff. A transformer whose negation was lost shows up immediately, and four
  panes currently depend on negation.
- **The pane-switching key equivalents still work.** `Preferences.mm:155` assigns them by index —
  `i < 9 ? '1' + i : @""` — so with six panes the live shortcuts are ⌘1 through ⌘6, not ⌘1–⌘9.
  Testing ⌘7 proves nothing.
- **The responder chain still works.** Pane switching sets first responder from `nextValidKeyView`
  (`Preferences.mm:50-54`); tab order within a pane must be sensible.
- **Panes size correctly** — see Risks.
- **Automated where possible.** The channel mapping performed by `OakSoftwareUpdateChannelTransformer`
  is pure logic and should be tested. **Creating a `Preferences_test` target is part of this work** —
  verified: no such target exists in `project.yml`, there is no `Frameworks/Preferences/tests/`
  directory, and nothing anywhere exercises this framework. Follow the `SetupAssistantCore`
  precedent: testable logic lives where a test binary can link it.

## Risks

**Pane sizing, and this one has already shipped here.** `OakTransitionViewController` pins the pane
to its `fittingSize`. `CLAUDE.md` records the Terminal pane appearing as a dead click for months
because an empty view was pinned to a `fittingSize` of 0×0 with the previous pane still visible
underneath. A SwiftUI `Form` in an `NSHostingView` must report a sane `fittingSize` or that
reproduces — and it fails silently, looking like a rendering glitch rather than a sizing bug. The
first pane proves this or the design is wrong.

**Second Swift-bearing target.** The app target's Swift support was proven by spike; a static library
target is a different configuration and has never been tried here.

**No test coverage exists to regress.** Nothing under `Frameworks/Preferences/` is tested today, so
there is no safety net beneath any of this beyond the defaults diff and manual checks.

**A long-lived branch.** Holding six panes for one release means the branch stays open a while, and
Bundles alone could dominate that. Sequencing the simple panes first keeps the branch useful and
mergeable earlier if the decision changes.
