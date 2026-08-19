Title: Handoff

# Handoff

The polished snapshot: where the project is, what is decided, and what is next.
`STREAM.md` is the play-by-play with the evidence behind each decision; read this
first, then that only when you need the reasoning.

## What this is

`sdenike/textmate` — an unaffiliated, community-maintained fork of TextMate
targeting macOS 26 and Apple Silicon. Hard constraints, declared by the
maintainer and enforced throughout:

- **arm64 only** — no x86_64 fallbacks anywhere, including vendored binaries
- **System Ruby 2.6.10 only** — no bundled Rubies, no downloads, no 1.8 code
- **Forward compatible** (macOS 26+), zero traces of Ruby 1.8

## Current state

| | |
|---|---|
| Released | **v3.0.0-revived.26** — Setup Assistant, PR #19 |
| Unreleased | none |
| Phases complete | 0-5, 7 |
| Phase 6 | remainder in progress — QuickLook done, onboarding island done, Preferences/About/update-sheet islands not written |
| Phases remaining | 6 (remainder), 8 (shared modules), 9 (optional LSP) |
| Build | `TextMate.xcodeproj`, generated from `project.yml` by XcodeGen |
| Bundle | 26,012 KB — **1,916 KB smaller than the `undead` baseline** |

## Phase 6 was closed early — it is not complete

Phase 6 was declared done when `NSVisualEffectView` disappeared from the tree. That was the glass
criterion, not the phase. The spec's Phase 6 paragraph
(`docs/superpowers/specs/2026-08-12-textmate-revived-design.md`) is much wider, and several items
were never started:

| Spec item | Status | Size |
|---|---|---|
| Tahoe tab bar | **done** | — |
| `NSGlassEffectView` on chrome surfaces | **done** | — |
| Scope bar | **already done — since 2014** | none |
| Back/forward navigation | **already done — since 2018** | none |
| **QuickLook extension** | **done and verified** — previews render syntax highlighted | — |
| SwiftUI islands: onboarding | **done** — Setup Assistant, first launch and `Help → Setup Assistant…` | — |
| SwiftUI islands: Preferences, About, update sheet | not done | large |
| `NSSplitViewController` sidebar | not started | large — defer |
| `NSRulerView` gutter | not done | large — **do not do** |

**QuickLook is fixed and verified.** The old `.qlgenerator` used callbacks retired at macOS 12 and
macOS had stopped loading it, so previews were silently broken in every shipped build.
`Contents/PlugIns/QuickLookExtension.appex` replaces it. Two real defects had to be fixed:

- **`.appex` requires EXACT UTIs.** `.qlgenerator` matched by *conformance*, so its three-entry list
  covered every language beneath `public.source-code`. An extension gets no such treatment: a `.rb`
  file is `public.ruby-script` and matches none of them, so macOS never invoked it. It now declares
  ~165 exact UTIs.
- **`path::passwd_entry()` (`Frameworks/io/src/path.cc`) looped forever.** It retries `getpwuid`
  around a modal alert until `access(pw_dir, R_OK)` succeeds — unbounded, assuming a human answers.
  Sandboxed, `access()` fails on a valid home and the alert cannot display, so it spun at 100% CPU.
  **That would hang any non-interactive caller** — `mate`, `tm_query`, the test runners. Now bounded.

**A whole class of resources never shipped.** `assemble_resources.sh` globbed only `*.png`, `*.pdf`,
`*.tiff`, so since Phase 2 every other framework resource was silently dropped: **12 xibs never
compiled** (Terminal preferences, the entire Bundle Editor, encoding customisation, tab-size picker,
pasteboard selector), plus `Charsets.plist`, `svn_status.xslt`, `bindings.plist`, 36 `.icns` and the
HTMLOutput support files — all referenced by live code. `Contents/Resources` went 164 -> 216 files.

**This was the third recurrence of the same glob bug** and the first not about images. Each time it
was found by a user noticing something drew empty, never by the build. `bin/verify_resources.sh` now
does a full set-difference at build time and fails when a framework resource does not ship. Never
verify this with a threshold; only a set comparison works.

## Things that will mislead you about QuickLook

- `qlmanage -m plugins` **cannot see app extensions** (Safari's own is absent too) and `qlmanage -p`
  **crashes on any `.appex`**, Apple's included. Use `pluginkit -m -p com.apple.quicklook.preview`.
  Deploying drops registration — restore with `pluginkit -a <path>`.
- Extensions **must** be sandboxed; `pkd` refuses otherwise. The home root must be granted read-only
  or `path::passwd_entry()`'s `access()` check fails.
- Deleting a build does **not** unregister it. Stale LaunchServices claims from deleted copies
  pre-empted the new extension; clean up with `lsregister -u`, not just `rm -rf`.

## Performance, as measured

Phase 7's headline: **opening a large file was the real problem**, and it had
never been measured through six prior phases.

| metric | before | after |
|---|---|---|
| 1 MB file, reopen | 15,559 ms | **5,820 ms** |
| 1 MB file, cold open | — | **2.3× faster** |
| Launch | — | **28% faster than `undead`** |
| Bundle | 27,704 KB | **26,012 KB** |

Two changes produced all of it:

1. **`bundles::value_for_setting` discarded its whole cache past 1000 entries**
   (`wrappers.cc`). A real 1 MB C++ file produces ~61,000 distinct scopes, so the
   cache filled, wiped and refilled without ever paying off. Bound raised.
2. **The scope-selector matcher had no early-out** (`scope/src/match.cc`). Each
   cache miss compared the scope against all 53 installed settings items in full.
   A literal-first-component check now rejects most before the recursive matcher
   runs.

## What was tried and rejected — do not retry without reading why

Each is recorded in `STREAM.md` with numbers:

- **Keying the settings cache on `scope_t::hash()`** — 13× *slower*. That hash
  XOR-chains atoms into the parent's, and nesting repeats atoms, so distinct
  scopes collapse onto shared values and lookups degenerate into bucket walks.
- **Deferring the symbol list until after first paint** — flat, twice, both
  implementations correct. The parser already yields every ~10-20 lines, so the
  main thread was answering in ~470 ms before any change. There was no freeze to
  break up.
- **Warming the settings cache from the parser's background queue** — 8% faster
  and **crashed on quit** (static destroyed on the main thread while a background
  block still used it). Reverted.
- **`-Os` -> `-O2`** — inconclusive; within-build variance exceeded the effect.
  Costs 908 KB certain. Note `-Os` is Xcode's own Release default.
- **Rewriting hot paths in Rust or Swift** — wrong layer. The cost was ~3.25M
  selector evaluations; a rewrite runs the same number with better codegen while
  adding a second toolchain.

## Things that will mislead you

- **Cross-session benchmark comparisons are invalid.** The same unchanged
  `undead` binary measured 661 ms at Phase 0 and ~1137 ms months later. Measure
  both sides in one session or measure nothing.
- **This machine drifts within a session too.** Identical builds have varied 28%
  across three rounds. Alternate sides and report spreads.
- **`measure-open.sh` waits for CPU quiescence**, so it cannot show a win from
  deferring work. `measure-responsive.sh` measures time-to-responsive instead.
- **TextMate restores open documents at launch**, so a hand-rolled
  open-and-wait-for-idle loop times session restore, not the open. Use the
  harnesses.
- **An incremental build keeps resources you deleted.** `assemble_resources.sh`
  copies and never removes. Delete `Resources/About` before trusting a size figure.
- **`xctrace --launch` resolves by bundle id, not path**, so it profiles
  `/Applications/TextMate.app` rather than your build. Use `sample`.

## Third-party attribution

Audited in full: Onigmo (BSD-2), kvdb (MIT), xdiff (LGPLv2.1) and Dialog/Dialog2
(repo GPLv3) are each **compiled, linked and actively called**, so all four
credits on the About window's Legal page are required and must stay. Nothing
shipped is uncredited. `bin/CxxTest` carries a licence but is provably not
shipped — our test runner is a home-grown reimplementation.

## Tab dragging

Reorder and tear-off are phases of **one** `NSDraggingSession` (`OakTabBarView.mm:1002`). Tear-off
is not a separate gesture — it is the fallback taken only when nothing accepted the drop, evaluated
once at release. Knowing that is the difference between a five-line fix and a rewrite.

Tear-off requires the release to be **60 pt from the tab bar's own rect**, measured to the rect
rather than its centre, so travelling along the bar never detaches a tab however far it goes. This
came from reviewer feedback on PR #15 that rearranging was too easy to turn into an accidental
detach.

**Dragging a single tab onto another window's tab bar already merges it on release** —
`performDragOperation:` to `performDropOfTabItem:...`. Do not rebuild that.

A window-onto-tabbar merge gesture (drag a whole window over another's tab bar, hold, merge) is in
progress. `performWindowDragWithEvent:` gives no progress callbacks, so it must be observed via
window-move notifications and a hit-test.

**GUI gestures cannot be verified in the agent sandbox** — no way to synthesise a sustained
mouse-down/move/up. Anything claiming otherwise should be checked: one such claim turned out to have
been made against `/Applications/TextMate.app`, an older installed release, not the build under test.

## Next

Nothing is in flight. The tree is clean and the working branch is
`phase-6/swiftui-onboarding`. [PR #18](https://github.com/sdenike/textmate/pull/18) was merged as
`a8bc6398` and **v3.0.0-revived.25 is published**.

### Phase 6 remainder — SwiftUI islands

The only spec item still genuinely open. The spec's own words
(`docs/superpowers/specs/2026-08-12-textmate-revived-design.md:236`):

> SwiftUI islands for Preferences, About, onboarding, update sheet, using #1467's `OakSwiftUI`
> bridge. *Gate:* visual parity pass, no regressions in the responder chain or key equivalents.

**Swift is proven to work here** — spiked 2026-08-18, full contract in `CLAUDE.md`.
`CLANG_ENABLE_MODULES = NO` is not a blocker, `import SwiftUI` compiles, and the app target takes a
`.swift` file with no build-setting changes at all. Two constraints came out of that spike and they
shape every island: Swift declarations must be `public` to be visible to ObjC++ at all, and the
bridging header must be a narrow, self-contained, pure-ObjC shim rather than a pointer at the app's
real ObjC++ headers.

**Onboarding is done** — spec at
`docs/superpowers/specs/2026-08-18-setup-assistant-design.md`, implemented 2026-08-18 across eight
tasks on `phase-6/swiftui-onboarding`. It ships as a three-step **Setup Assistant** (welcome,
appearance, bundles) that replaces `FirstLaunchBundleInstaller`'s modal, runs once at first launch
(gated on a new `didRunSetupAssistant` default so existing users see it too — the Help entry point
does not consult that gate and always shows), and is re-runnable from `Help → Setup Assistant…` with
current state reflected rather than a blank wizard. The `mate` CLI step was considered and cut.
`bin/build` and `bin/build TextMate/test` (14 tests) pass. Two things remain before this branch
merges, both human-only and out of the agent sandbox: the maintainer's manual walk of the five
first-launch scenarios the spec names, and a green CI run on the pushed branch.

**The maintainer's manual walk already found one bug, now fixed, and it uncovered a second, deeper
one that isn't.** The bundles step sourced from `FirstLaunchBundleInstaller.candidateSpecs`, which
excludes installed bundles — empty step for anyone who already has the default tier. Fixed
2026-08-19: it now lists every shipped-tier bundle, installed ones checked and disabled (see
STREAM.md for the full diff). But that fix depends on `BundleSpec.origin` correctly marking
default-tier bundles as `TMBundleOriginShipped`, and `BundleRegistry.seedShippedDefaults`
(`Frameworks/BundlesManager/src/BundleRegistry.mm`) only sets that for a UUID it has never tracked
before — unlike `seedMandatory`, it does not re-assert origin for one already in the persisted state
file. Simulated against this machine's real `Bundles.plist`: **0** of 41 default-tier bundles come
back `Shipped` once a profile has been through a second reload, which is any profile that's been
launched more than once. Likely also silently affects the *Preferences → Bundles* "recommended"
badge (`BundlesManager.mm:1012`, same check). Not fixed here — out of the file list this task
scoped, and needs its own look at whether unconditional re-tagging is safe for every case
`seedShippedDefaults` handles.

It was the right island to start with because it is the only one of the four with no existing
implementation — nothing to reach parity with, so a mistake costs only itself.

Preferences, About and the update sheet are each large: together roughly 1,945 lines of working
AppKit whose behaviour a SwiftUI rewrite has to match exactly, including key equivalents and the
responder chain the gate names.

The rest of Phase 6 is settled and should not be reopened:

- **Scope bar** and **back/forward navigation** — already present since 2014 and 2018.
- **`NSRulerView` gutter** — recommended **against**. It would delete ~600 lines of better-fitted
  code for a system class that does not model multi-column icons.
- **`NSSplitViewController` sidebar** — large, with no forcing function. Defer.

### Phase 8 — extract shared modules

> SwiftPM package repo with `RevivedUpdater`, `RevivedGlass`, `RevivedSettings`. Consumed by
> TextMate Revived; adopted by Hidden Bar / White Rabbit / Smilodon later. **Extract only what a
> second app demonstrably needs.** *Gate:* TextMate Revived builds against the package as an
> external dependency.

That constraint is the blocker: no second app consumes these yet, so what a second app "demonstrably
needs" is currently unknowable. Starting Phase 8 before one does means guessing at the API and
extracting the wrong surface. Either adopt one of the three apps first, or accept that the extraction
will be revised once a real consumer exists.

### Phase 9 — optional: LSP and Copilot

> #1467's LSP client, Copilot ghost text, Cmd+P palette. Gated on explicit approval; held out because
> it is the largest chunk of new code, the one thing reviewers pushed back on, and not among the
> stated goals.

Do not start this without being asked for it by name.

### Requested by the maintainer, belonging to no phase

- **Quick Look preview theme picker.** The extension reads `darkModeThemeUUID`; the maintainer wants
  the preview theme chosen explicitly rather than inherited.
- **File-type association UI in Settings** — `LSSetDefaultRoleHandlerForContentType`, so TextMate can
  claim file types from within the app. Scoped, not built.
- **The window-merge gesture has never been tested by a human**, particularly with an unsaved
  document. GUI gestures cannot be synthesised in the agent sandbox; this needs the maintainer.
- **Georg Seifert (`schriftgestalt`) offered a UI PR.** Unanswered.

### The next real performance lever

Before any further micro-optimisation: the remaining open-time cost is structural. The whole file is
parsed at open rather than the visible region — `set_grammar` dirties the entire buffer and batching
stops at EOF, never at the viewport. That is a larger change than anything in Phase 7, and it is
where the time actually is.
