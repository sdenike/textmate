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
| Unreleased | **Phase 6 is complete on `master`** — all 6 Settings panes, the update sheet and About are SwiftUI; zero xibs in `Frameworks/Preferences`; no `WKWebView` in the app's own chrome. Plus the `mate` and QuickLook version-drift fixes. |
| Phases complete | 0-7 |
| Phase 6 | **complete** — QuickLook, onboarding, all 6 Settings panes, the update sheet and About. Everything merged; no open PRs. |
| Phases remaining | 8 (shared modules), 9 (optional LSP) |
| Build | `TextMate.xcodeproj`, generated from `project.yml` by XcodeGen |
| Bundle | 28,060 KB — up 276 KB from About's structured changelog data; see STREAM.md |

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
| SwiftUI islands: Settings panes | **all 6 done** — Software Update, Projects, Variables, Files, Terminal, Bundles | — |
| SwiftUI islands: Settings — Terminal | **done** — privileged `mate` install stays ObjC++ by design; the framework's last xib is gone | — |
| SwiftUI islands: Settings — Bundles | **done** — 903 lines ported; see STREAM.md for the three stated losses | — |
| SwiftUI islands: About | **done** — the "settled, do not reopen" call below was revised once the Changes page had a plan that didn't need a Markdown renderer | — |
| SwiftUI islands: update sheet | **done** and merged | — |
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

`master` is at v3.0.0-revived.26 plus six ported Settings panes, **none released**. Two more islands
— the update sheet and About — are done but sit one commit each further out, on their own unmerged
branches (`phase-6/swiftui-update-sheet`, then `phase-6/swiftui-about` on top of it), neither yet
merged to `master`.

**The release decision is unmade and is the maintainer's.** Cutting a `CHANGELOG.md` version heading
publishes a signed, notarized build and updates the Homebrew cask. The standing decision was to hold
everything and ship together rather than have Settings, or the rest of the app's own chrome, reach
users half-modern. With Bundles, the update sheet and About all now done, that mainly leaves merging
the two outstanding branches and making the call.

### Phase 6 remainder — Settings panes, the update sheet and About are all now done

**All six Settings panes are ported** (detail in STREAM.md — Terminal and Bundles landed most
recently, Bundles keeping three stated, deliberate losses rather than hiding them). The pattern is
documented in `CLAUDE.md`'s *Settings panes as SwiftUI islands* section — read that before touching
one again; it records seven traps that each cost a build cycle or a shipped defect, including one
(`extern "C"`) that `Preferences_test` provably cannot catch.

Order and reasoning for the panes live in
`docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`.

**The update sheet is done**, on `phase-6/swiftui-update-sheet` — see that branch's own commit
(`feat(update): port the software-update sheet to SwiftUI`) and STREAM.md for what it changed; not
re-verified in detail from this entry.

**About is done**, on `phase-6/swiftui-about`. The "settled, do not reopen" call further down was
made because porting looked like it required writing a Markdown renderer for a 269 KB Changes page.
It was reopened once there was an answer to that specific objection: `bin/gen_about_data` parses
CHANGELOG.md and Legal.md into structured plists at build time (headings, categories and bullets as
real structure, one fenced code block pulled out verbatim, reference-style links resolved), and
SwiftUI renders that structure as layout, calling `AttributedString(markdown:)` only for inline
formatting inside each bullet — never a general renderer. All 202 releases render, verified against
the real `AttributedString(markdown:)` API rather than assumed (see that commit and `CLAUDE.md`'s
Swift section). `about/About.md` is gone — its 13 lines are written directly in SwiftUI instead,
per that same commit's reasoning.

Settled, do not reopen:

- **About** — *no longer settled; done.* See above: the objection was writing a Markdown renderer
  for the Changes page, and `bin/gen_about_data` answers it without one.
- **Scope bar** and **back/forward navigation** — present since 2014 and 2018.
- **`NSRulerView` gutter** — recommended against: deletes ~600 lines of better-fitted code.
- **`NSSplitViewController` sidebar** — large, no forcing function. Defer.

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

### The next real performance lever — the previous answer here was wrong

This section used to say the lever was parsing the visible region rather than the whole file.
**It is not, and it cannot be.** Parser state chains line to line from the top — line N's state is
the input to line N+1 — so there is no way to skip ahead to the viewport. You could only stop
*after* it, which leaves the symbol list, folding and spell-check incomplete.

The obvious replacement was also wrong. `initiate_repair` parses one line per dispatch, so a 64,219
line buffer costs 64,219 runloop round-trips; batching them measured **flat** (11× fewer dispatches,
1.0385 s → 1.034 s, inside a 2.9% spread) and was reverted. That is the third plausible parser change
to measure flat here, after two attempts at deferring the symbol list.

What the evidence points at instead is the **synchronous continuation** — `update_scopes` →
`did_parse` → `symbols_t::did_parse` → `bundles::value_for_setting` — which fires every
`limit_redraw` lines however the parse is dispatched. A profile taken before the Phase 7 fixes put
72% there; that figure predates both the cache-bound raise and the `does_match` fast-reject and has
not been re-measured.

**Measure before changing anything here.** `bin/build buffer/test` then `buffer_test -b` gives a
headless baseline in about a second, with no GUI and no interference with a running app.
