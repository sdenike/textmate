# TextMate Revived — Design

Date: 2026-08-12
Status: awaiting user review
Base repo: `sdenike/textmate` (fork of `textmate/textmate` @ `346b52b1`, 2021-10-12)

## Goal

Modernize the abandoned TextMate 2 codebase into **TextMate Revived**: an Apple Silicon-only,
macOS 26+ native editor that builds in Xcode, adopts Liquid Glass, updates itself from this
repository's GitHub Releases, installs via a Homebrew tap, launches fast, opens large files
fast, and stays small.

## Non-goals

- Cross-platform support. macOS only, arm64 only.
- Intel support. macOS 26 does not run on Intel.
- Rewriting the C++ text engine. See "The core is the asset".
- LSP / Copilot / command palette. Deferred to Phase 9, gated on explicit approval.
- Backporting to older macOS. Minimum is macOS 26.0.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| UI framework | **AppKit shell + SwiftUI islands** | Editor is a custom `NSView` over a bespoke C++ layout engine; SwiftUI has no equivalent primitive. SwiftUI used via `NSHostingView` for leaf panels only. |
| Liquid Glass | **AppKit `NSGlassEffectView`** | Verified present in the installed SDK. SwiftUI is not required to adopt it. |
| Build system | **Xcode project** (`.xcodeproj`) | User requirement. Rejected CMake: `-G Xcode` yields a non-tunable generated project and makes CMake a permanent build dep. |
| Updater | **Port textmatelives' GitHub-Releases updater** | Already shipping across 5 releases with signature verification and a prerelease channel. Arrives free with the Phase 1 merge. Rejected Sparkle: ~2MB and a third-party dep to replace something that works. |
| Base | **textmatelives/main, then port #1469 and #1467 selectively** | Three forks each own a different layer. Redoing their work buys nothing. |
| Bundle ID | `com.shelbydenike.${TARGET_NAME}` | User decision. Matches their other projects. |
| Language | C++23 core, Swift 6 for new code, existing ObjC++ glue retained | Rewriting working ObjC++ glue is churn with no user-visible payoff. |
| License | **GPLv3, unchanged** | Upstream is GPLv3 with no exceptions. A fork must remain GPLv3. |

## The core is the asset

`buffer` (AA-tree storage), `layout`, `editor`, `selection`, `regexp` (vendored Onigmo),
`scope`, `parse` — roughly 25K lines of pure C++ — are why TextMate opens a very large file
instantly. `OakTextView` (7.4K lines ObjC++) is a custom `NSView` driving that engine.

This code is not legacy debt. It is the product's differentiator and the reason the
"fast startup, fast file loading" goal is achievable at all. It is modernized in place
(C++23, warnings clean), never replaced.

Key structures, per `INTERNALS.md`: `oak::basic_tree_t` (AA-tree, O(1) indexed access),
`ng::detail::storage_t` (chunked byte storage), `ng::buffer_t`, `ng::indexed_map_t`
(segment tree), `ng::layout_t`.

## Prior art

Three forks exist. They are complementary, not competing.

| | textmatelives/main | #1469 (schriftgestalt) | #1467 (tectiv3) |
|---|---|---|---|
| Divergence | 130 ahead / 0 behind, 300 files | 77 commits, 550 files, +19412/−5842 | 100 commits, 599 files, +93590/−12276 |
| Updated | 2026-06-11 | 2026-08-10 | 2026-07-19 |
| Mergeable | true fork, same base | `MERGEABLE` / `CLEAN` | `CLEAN`, head `develop` |
| Min macOS | **26+, Apple Silicon only** | 12+ | 14+, arm64 |
| Build | rave/ninja (unchanged) | **`.xcodeproj`**, rave deleted, static linking | CMake+Ninja, 59 `CMakeLists.txt`, 63 `.rave` deleted |
| Deps removed | Cap'n Proto, license | license, crash reporter | **boost, ragel, sparsehash, Cap'n Proto, multimarkdown** |
| Updater | **GH Releases + signature verify, notarized CI** | disabled | deleted |
| UI | SF Symbols toolbar, first-run sheet | **Tahoe tab bar, `NSRulerView` gutter, `NSSplitViewController` sidebar, scope bar, back/forward nav, QuickLook extension, `.icon` asset** | command palette, formatters pane |
| Swift | none | none | **`OakSwiftUI`: 49 Swift files + `Package.swift`** |
| Ships | 11.4 MB `.tbz`, 5 releases | tagged only | no |

**Layer ownership:** textmatelives owns platform and distribution; #1469 owns Xcode and UI;
#1467 owns dependency purge and the Swift bridge.

**Conflict analysis.** #1467 ∩ #1469 = 204 shared files, but the overlap is dominated by
`*/default.rave` files that **both delete**. Deletion-vs-deletion is not a merge conflict.
The genuinely contested surface is the build system alone, resolved in favour of `.xcodeproj`.

#1467's dependency removals are **source-level** (`boost::variant` → `std::variant`,
sparsehash → `std::unordered_map`, ragel → committed generated state machines) and therefore
portable onto an Xcode build. We take its best work without taking its build system.

Correction to an earlier automated report: #1467 does **not** delete 45 frameworks. It deletes
`SoftwareUpdate`, `CrashReporter`, `network`, `updater`, `license`, the `SyntaxMate` app, and
the `bl` CLI. The larger count was an artifact of every framework losing its `default.rave`.

## Current state of the fork

- ~92K lines C++/ObjC++, 45 frameworks, 11 app targets, 27 MB.
- Build: `./configure` → `bin/rave` (50KB Ruby) → `build.ninja` → `ninja`.
- `APP_MIN_OS = "10.12"` (`default.rave:1`); dual-arch `-target macos-arm64` +
  `-target macos-x86_64` (`local-orig.rave:19-23`). Intel lives in build config, not in code.
- Bundle ID template `com.macromates.${TARGET_NAME}` (`Applications/TextMate/Info.plist:12`);
  version `v2.0.22`.
- 86 CxxTest files under `Frameworks/*/tests/`.
- 6 submodules: `bin/CxxTest`, `Applications/TextMate/icons`, `PlugIns/dialog-1.x`,
  `PlugIns/dialog`, `vendor/Onigmo/vendor`, `vendor/kvdb/vendor`.
- Build deps to eliminate: boost, Cap'n Proto, sparsehash, ragel, multimarkdown, ninja.

## SDK verification

Typechecked clean at `arm64-apple-macos26.0` against SDK MacOSX26.5 (Xcode 26.6):

- AppKit: `NSGlassEffectView`, `NSGlassEffectContainerView`, `NSGlassEffectViewStyle.clear` —
  all `API_AVAILABLE(macos(26.0))`.
- SwiftUI: `GlassEffectContainer(spacing:)`,
  `.glassEffect(.regular.tint(_).interactive(), in:)`.

## Architecture after the rebuild

```
TextMate Revived.app
├── Swift 6 / SwiftUI islands      Preferences, About, onboarding, update sheet
│                                  hosted in AppKit via NSHostingView
├── AppKit shell (ObjC++/Swift)    window, tabs, sidebar, gutter, toolbar,
│                                  responder chain, Liquid Glass surfaces
├── OakTextView (ObjC++)           custom NSView, event handling, drawing
└── C++23 core (static libs)       buffer · layout · editor · selection ·
                                   regexp(Onigmo) · scope · parse · theme ·
                                   settings · bundles · document · io · text
```

The 45 framework bundles collapse into a small number of **static** libraries linked into one
binary. Each currently-separate framework is a bundle dyld must locate and load at launch;
static linking removes that cost outright and is the single largest expected startup win.

Boundaries are preserved as static-library targets with public headers, so each subsystem
remains independently buildable and testable. Merging them into one target would destroy the
testability the 86 CxxTest suites depend on.

## Testing strategy

The 86 CxxTest suites are the **regression oracle for the entire migration**. Phase 0 captures a
baseline; every subsequent phase must keep them green before it is considered done. A phase
that cannot keep them green is a phase whose scope was wrong.

Benchmark harness, captured at Phase 0 and re-measured each phase:

| Metric | Method |
|---|---|
| Cold launch | `hyperfine` over `open -W -a`, cold caches |
| Bundle size | `du -sk` on the `.app`, plus per-binary `size` |
| Resident memory | `footprint` after idle settle |
| Large-file open | time-to-first-paint on a generated 100 MB file |
| Syntax-highlight throughput | time to fully parse a large known source file |

"Faster and smaller" is a claim that requires numbers. Without Phase 0 numbers, later phases
cannot substantiate it.

### Tests to be written

Keeping the 86 inherited suites green proves we broke nothing. It does not prove the new work
is correct. Each phase therefore ships new tests, and the phase is not done until they pass.

| Phase | New tests |
|---|---|
| 0 | Benchmark harness itself, checked in and reproducible from a clean clone |
| 1 | Post-merge smoke: app launches, opens a file, saves, quits |
| 2 | Build verification: `xcodebuild` clean-room build from a fresh clone with no Homebrew deps |
| 3 | One equivalence test per removed dependency — golden-value fixtures proving the replacement matches the old behaviour (CRC output, plist round-trip, parser state machines) |
| 4 | Settings-importer unit tests; bundle-ID migration; clean-install and upgrade paths |
| 5 | **Updater negative tests** — tampered payload rejected, wrong signing key rejected, downgrade rejected, malformed feed rejected |
| 6 | Responder-chain and key-equivalent regression tests; Liquid Glass renders on macOS 26 without layout breakage |
| 7 | Benchmark assertions with thresholds — CI fails if launch time or bundle size regresses beyond tolerance |

The Phase 5 negative tests are the highest-value suite in the project. An updater that accepts a
tampered payload is a remote code execution path into every user's machine, and positive tests
("a good update installs") cannot detect that failure.

**Frameworks:** CxxTest stays for the C++ core — rewriting 86 working suites into XCTest is
churn with no payoff. XCTest for new Swift and ObjC++ code. XCUITest for launch smoke only,
kept deliberately thin because UI tests are slow and brittle.

## Error handling and risk

| Risk | Mitigation |
|---|---|
| Phase 1 merge conflicts across 300 files | Merge on a branch; tests are the gate. Main loop handles conflicts, never delegated. |
| Porting #1469 UI onto a textmatelives base diverges | Port commit-by-commit by theme, not as one squash. Each theme is independently revertable. |
| Static linking breaks the plugin/bundle model | Bundles are data (grammars/commands), not code. `PlugIns/dialog` is the only real code plugin; verify explicitly. |
| Updater signature verification is a security surface | Audited in the main loop, never delegated. Signature verification and key handling are never mechanical edits. |
| Notarization requires Apple Developer credentials | External prerequisite. Blocks Phase 5 only; Phases 0-4 and 6-8 proceed without it. |
| Bundle ID change orphans existing settings | First-launch opt-in importer, Phase 4. |
| Onigmo 5.13.5 is from ~2016 | Evaluate updating during Phase 3; regex semantics are load-bearing, so any bump is gated on the `regexp` test suite. |

## GPL compliance

Upstream is GPLv3 with no exceptions. Non-negotiable obligations:

- Fork remains GPLv3; `LICENSE` and `COPYING` stay.
- Upstream authorship credited; MacroMates' copyright notices preserved.
- Complete corresponding source published for every binary release.
- Rename is required to avoid trading on the MacroMates "TextMate" trademark, and the README
  must state plainly that this is an unaffiliated community fork.

## Phases

Each phase ends with a launchable app and green tests.

**Phase 0 — Baseline, safety net, and hygiene.** Build as-is with rave/ninja. Run all 86 suites.
Capture reference binary and benchmark numbers. Add all three forks as git remotes. Replace the
3-line `.gitignore` with a comprehensive one; install the `gitleaks` pre-commit hook; enable
GitHub secret scanning with push protection; add the `github.repository` guard to the existing
workflow. Create milestones for Phases 0-9 and the issue labels.
*Gate:* tests green, benchmarks recorded, a deliberately planted dummy credential is rejected by
both the pre-commit hook and push protection.

**Phase 1 — Rebase onto textmatelives.** Merge its 130 commits. Delivers arm64-only, macOS 26
target, Cap'n Proto gone, license framework gone, dead `api.textmate.org` calls gone, notarized
CI, working GH-Releases updater.
*Gate:* tests green, app launches.

**Phase 2 — Xcode migration.** Port #1469's project. Collapse frameworks into static libs.
Delete `configure`, `bin/rave`, all 63 `.rave` files, `.travis.yml`. Strip `-target macos-x86_64`.
Swift 6 language mode, C++23. CI to `xcodebuild`.
*Gate:* `open TextMate.xcodeproj` → Cmd-B → runs. CI green.

**Phase 3 — Dependency purge.** Port #1467's source-level removals (boost, sparsehash, ragel,
multimarkdown). Replace `network` with `URLSession`. Delete `crash`/`CrashReporter`,
`SyntaxMate`, `bl`.
*Gate:* zero Homebrew deps to build. Size and launch delta measured against Phase 0.

**Phase 4 — Identity.** `com.macromates.${TARGET_NAME}` → `com.shelbydenike.${TARGET_NAME}`.
App name, icon, strings, credits, GPL attribution. First-launch opt-in settings importer.
*Gate:* clean install and upgrade-from-TextMate both verified.

**Phase 5 — Updates and distribution.** Updater points at `sdenike/textmate-revived` releases.
GitHub Action: build → sign → notarize → staple → publish → update feed. Cask published to the
central tap (Phase 5a), auto-bumped by the same action.
*Gate:* a real update installs itself end-to-end from a published release.

**Phase 5a — Central Homebrew tap.** Independent of the TextMate work; can run in parallel from
Phase 0 onward and pays off for Hidden Bar immediately. See "Homebrew strategy" below.
*Gate:* `brew tap sdenike/tap && brew install --cask hidden-revived` works, and an existing
`sdenike/hidden-revived` user is migrated automatically by `brew update`.

**Phase 6 — UI and Liquid Glass.** Port #1469's UI commits: `NSSplitViewController` sidebar,
`NSRulerView` gutter, Tahoe tab bar, scope bar, back/forward navigation, QuickLook extension
replacing the deprecated generator. Then `NSGlassEffectView` on toolbar/sidebar/tab bar, with
`NSGlassEffectContainerView` grouping adjacent surfaces so they merge correctly. SwiftUI islands
for Preferences, About, onboarding, update sheet, using #1467's `OakSwiftUI` bridge.
*Gate:* visual parity pass, no regressions in the responder chain or key equivalents.

**Phase 7 — Performance.** Static-link to eliminate dylib loads. Instruments profiling against
Phase 0. Lazy bundle index, deferred subsystem init, dead-strip and LTO tuning.
*Gate:* measured improvement over Phase 0 on launch, size, and large-file open.

**Phase 8 — Extract shared modules.** SwiftPM package repo with `RevivedUpdater`,
`RevivedGlass`, `RevivedSettings`. Consumed by TextMate Revived; adopted by Hidden Bar /
White Rabbit / Smilodon later. Extract only what a second app demonstrably needs.
*Gate:* TextMate Revived builds against the package as an external dependency.

**Phase 9 — Optional: LSP and Copilot.** #1467's LSP client, Copilot ghost text, Cmd+P palette.
Gated on explicit approval; held out because it is the largest chunk of new code, the one thing
reviewers pushed back on, and not among the stated goals.

## Homebrew strategy

One central tap for every app the user ships, replacing the current per-app tap
(`sdenike/homebrew-hidden-revived`).

**Naming.** Repos must follow `homebrew-<repository>` to support shorthand tapping. So
`sdenike/homebrew-tap` → `brew tap sdenike/tap`. Scaffold with
`brew tap-new sdenike/homebrew-tap`, which also generates publishing workflows.

**Rationale.** One tap command covers the whole catalog; one auto-bump workflow is maintained
instead of one per app; `brew upgrade` covers everything at once; casks and formulae coexist
(`Casks/` for GUI apps, `Formula/` for CLI-only tools).

```
sdenike/homebrew-tap
├── Casks/
│   ├── textmate-revived.rb
│   └── hidden-revived.rb
├── Formula/                 # CLI-only tools, if any
└── .github/workflows/       # shared auto-bump on upstream release
```

**Migrating existing hidden-revived users.** Two mechanisms exist and are not interchangeable:

- `cask_renames.json` — renames a token *within one tap*. Docs require the target cask to exist
  in the same tap. Not applicable here.
- `tap_migrations.json` — moves a cask/formula to a *different* tap. This is the one we need.

Procedure: add the cask to the new tap first, then in the old tap delete the cask file and add:

```json
{ "hidden-revived": "sdenike/tap" }
```

Existing users migrate on `brew update`. **The old repository must not be deleted** — archived
is fine, but brew has to read `tap_migrations.json` to perform the redirect. Deleting it strands
every existing installation.

**Confidence note.** Homebrew's migration document states migrations should occur within the
Homebrew organization. That is policy governing *official* taps, not a technical restriction on
personal taps — `tap_migrations.json` is a file the tap supplies. Verify end-to-end with a
throwaway install before relying on it.

**Token collision.** `homebrew/cask` already ships a `textmate` cask (pinned to v2.0.23). Our
token is `textmate-revived`, so there is no collision; if one ever arises, the fully-qualified
`sdenike/tap/textmate-revived` resolves it.

## Secrets and repository hygiene

**Hard requirement. `sdenike/textmate` is a public repository — anything committed is
world-readable and harvested by automated scrapers within minutes of the push.**

Never committed, at any point, for any reason:

- Signing identities and private keys: `*.p12`, `*.cer`, `*.crt`, `*.pem`, `*.key`,
  `*.keychain`, `*.keychain-db`
- App Store Connect API keys: `AuthKey_*.p8`
- Provisioning profiles: `*.mobileprovision`, `*.provisionprofile`
- Notarization credentials: Apple ID, app-specific passwords, credential plists
- The update-feed signing private key, if one is introduced
- `.env`, `.envrc`, anything under `secrets/`
- `local.rave` and any machine-local generated config

Where they live instead: **GitHub Actions encrypted secrets** for CI, **macOS Keychain**
locally. CI imports the certificate into a temporary keychain created at job start and
destroyed at job end, never into the default login keychain.

Defence in depth — `.gitignore` is the first layer, never the only one:

1. Comprehensive `.gitignore`, written in Phase 0 before any signing work exists.
2. Pre-commit hook running `gitleaks git --pre-commit --staged .`, blocking the commit locally.
   (`gitleaks protect --staged` is the deprecated 8.x form; verified against gitleaks 8.30.1.)
3. `gitleaks` in CI on every pull request, catching whatever bypassed the hook.
4. GitHub secret scanning **with push protection** enabled on the repository — free for public
   repos, and it rejects the push rather than merely reporting it afterwards.
5. No secret ever echoed into CI logs; mask any derived value with `::add-mask::`.

**If a secret does land: rotate first, scrub history second.** A credential pushed to a public
repository is compromised from that moment. Rewriting history does not un-leak it, and treating
a force-push as the fix is the most common way this goes wrong.

## CI policy

Verified: `sdenike/textmate` is `PUBLIC`, so CI is permitted there.

Standing rule — **workflows run only on public repositories.** Any private repository (a scratch
fork, an experimental clone) must not run Actions.

Enforcement is a guard on every job:

```yaml
# Phase 0 through Phase 3, before the rename:
if: github.repository == 'sdenike/textmate'
# updated in Phase 4 alongside the rename:
if: github.repository == 'sdenike/textmate-revived'
```

The guard string is part of the rename checklist in Phase 4 — missing it silently disables all
CI, so the Phase 4 gate must include "CI still runs after rename".

Repository-name matching is preferred over inspecting the privacy flag: it is unambiguous across
all trigger types, and it additionally prevents forks from burning macOS runner minutes, which
are billed at a multiple of Linux.

`.travis.yml` is deleted in Phase 2 — it targets xcode7.2 and is dead weight.

## GitHub history discipline

Work is recorded in the repository as it happens, so the project has a searchable history rather
than a wall of unexplained commits.

- **Milestone per phase.** Phase 0 through Phase 9.
- **Issue per work item**, labelled by phase and type, assigned to its milestone.
- **Branch per issue**, named `phase-N/short-slug`.
- **Pull request per issue**, body stating what changed, why, and the verification output that
  proves it. Linked with `Closes #N` so the merge closes the issue and records the link.
- **Squash merge**, keeping one commit per unit of work on `master`.
- **Outcomes commented onto issues** — benchmark deltas, test results, decisions taken and
  rejected — so the reasoning survives past the session that produced it.
- **`CHANGELOG.md` generated per milestone** from merged pull request titles.

**Attribution when porting.** Any pull request carrying work from `textmatelives/main`,
PR #1467, or PR #1469 names the source commit SHAs and the original author in its body. This is
both a GPLv3 obligation and basic courtesy to people whose work saves us months.

## Agent allocation

| Work | Route |
|---|---|
| Locating call sites, mapping directories | `scout` (Haiku) |
| Bulk renames (Phase 4), build-config edits (Phase 2) | `mechanic` (Sonnet) |
| Scoped ports where the diff is already known | `builder` (Sonnet) |
| Merge conflicts, architecture, signing, updater | main loop — never delegated |

Phases 3, 6, and 7 parallelize across framework boundaries. Phases 1 and 2 are inherently serial.

## Assumptions

Stated explicitly so they can be corrected rather than discovered late:

1. Repo renamed to `sdenike/textmate-revived`; GitHub redirects the old path, so existing
   clones and the updater endpoint keep working.
2. App display name "TextMate Revived"; `.app` bundle named `TextMate Revived.app`.
3. CLI binary keeps the name `mate`, installed by the cask as `mate-revived`, with an opt-in
   `mate` symlink so it does not collide with an official TextMate install.
4. Installs alongside the official TextMate rather than replacing it.
5. A Developer ID certificate and notarization credentials will be available before Phase 5.
6. Shared-module repo name to be confirmed at Phase 8; not needed earlier.

## Shared-module repository (Phase 8)

**Licensing is the binding constraint, not taste.**

TextMate Revived is GPLv3. Two rules follow, and violating either is a licensing failure rather
than a style problem:

1. **The shared repository must be public.** GPLv3 requires complete corresponding source for
   every distributed binary. If TextMate Revived links a module from a private repository, it
   cannot be legally distributed at all.
2. **Clean-room content only.** Any module extracted from TextMate's tree is a derived work and
   remains GPLv3 permanently. Linking such a module into White Rabbit, Smilodon, or Redpill
   would pull those apps to GPLv3. Anything GPL-derived — including textmatelives' updater
   internals — stays in the TextMate Revived repository and never migrates out.

**License: MIT.** It is GPL-compatible, so TextMate Revived may consume it, and permissive, so
closed apps may consume it. It is the only choice that flows in both directions.

Private also conflicts with two decisions already taken: no CI on private repositories, which
would leave a library four apps depend on untested; and private SwiftPM dependencies require
token authentication in every consuming repository's CI.

**Name:** `sdenike/construct` → package `Construct`, products `ConstructUpdater`,
`ConstructGlass`, `ConstructSettings`. Matches the existing Matrix-themed naming alongside
White Rabbit and Redpill.

**Platform floor.** The package declares the *lowest* macOS version across consuming apps, not
macOS 26. Liquid Glass helpers are gated `@available(macOS 26, *)` with a documented fallback,
otherwise Hidden Revived cannot adopt the package at all.

## Resolved

- **Apple Developer account: active.** Already used for White Rabbit, Smilodon, and Redpill.
  Phase 5 is unblocked; Developer ID signing and notarization proceed as planned.

## Open questions

- Should the QuickLook extension ship in the same bundle or as a separate target? Decided in
  Phase 6 once #1469's implementation is examined.
