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
| Released | **v3.0.0-revived.24** |
| Phases complete | 0-5, 7 |
| Phase 6 | **partially complete — see below** |
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
| **QuickLook extension** | **built on `phase-6/quicklook-extension`, unmerged** | done, needs one check |
| SwiftUI islands: onboarding | not done — no existing implementation | small-medium |
| SwiftUI islands: Preferences, About, update sheet | not done | large |
| `NSSplitViewController` sidebar | not started | large — defer |
| `NSRulerView` gutter | not done | large — **do not do** |

**QuickLook was dead, and is rebuilt.** The old `.qlgenerator` used callbacks retired at macOS 12 and
macOS had stopped loading it entirely, so previews silently did not work.
`Contents/PlugIns/QuickLookExtension.appex` replaces it — sandboxed, conforming to
`QLPreviewingController`, reusing the old render logic. Built on `phase-6/quicklook-extension`,
**not merged**.

**Two QuickLook tooling facts that will waste your time otherwise:**

- **`qlmanage -m plugins` cannot see app extensions.** Safari's own `.appex` is absent from it too;
  the command predates app-extension QuickLook by 14 years. Use
  `pluginkit -m -p com.apple.quicklook.preview`.
- **`qlmanage -p` crashes on any `.appex`**, including Apple's own. There is no CLI way to prove a
  preview renders — Finder's Space-bar preview is the only test.

**Unresolved:** the extension is sandboxed, but `initialize()` reads grammars and themes from
`~/Library/Application Support/TextMate/`. If the sandbox blocks that, the existing fallback quietly
degrades to unstyled plain text rather than failing. Space-bar a `.rb` in Finder: highlighted means
working, plain text means the sandbox is blocking, nothing means not rendering.

**Scope bar and back/forward were never missing.** `OakScopeBarView` dates to 2014 with five live
callers; `goBack:`/`goForward:` to 2018, wired into the menu. Both are original upstream features
that happen to match the spec's wording. The spec item is stale, not unbuilt.

**The sidebar entry in an earlier version of this table was a false positive.** The one
`NSSplitViewController` reference is `BundleEditor.mm` (2021, upstream) — the Bundle Editor's own
internal split, unrelated to the file browser, which is still hand-sized by frame maths.

**Do not adopt `NSRulerView` for the gutter.** `GutterView` is a ~600-line multi-column
data-source/delegate design drawing per-line icons; `NSRulerView` models tick marks and has no
equivalent concept. Adopting it means reimplementing everything inside a worse-fitting container.

**#1469 and #1467 are not portable.** #1469 is `+19,490/−5,877` across 550 files and adds whole new
applications; the Liquid Glass spec already ruled it out as "a fork-sized rewrite [that] does not
lift out as a single piece". #1467's `OakSwiftUI` was built against a tree that had *deleted*
`SoftwareUpdate` and `CrashReporter`, so its views do not correspond to this fork's code. Treat the
remainder as write-from-scratch.

**Swift groundwork is already laid, with one landmine.** `Xcode/Base.xcconfig:59-61` sets
`SWIFT_VERSION = 6.0` with a comment naming Phase 6's islands as the first consumer. But
`CLANG_ENABLE_MODULES = NO` is marked "REQUIRED off, do not remove" (an xdiff/Darwin module
collision), and Swift↔ObjC++ interop normally wants modules on. That interaction is **untested** and
is the first thing to prove before committing to any SwiftUI work.

The lesson worth carrying: a phase closed against one of its criteria is not a phase closed. Check
the spec paragraph, not the thing you happened to be working on.

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

Phase 8 (shared modules) and Phase 9 (optional LSP). Before more micro-optimising,
note that the remaining open-time cost is structural: the whole file is parsed at
open rather than the visible region (`set_grammar` dirties the entire buffer and
batching stops at EOF, never at the viewport). That is the next real lever, and it
is a larger change than anything in Phase 7.
