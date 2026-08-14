# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork constraints

This is `sdenike/textmate` (remote `origin`), a fork of `textmate/textmate` targeting macOS 26 /
Apple Silicon. `textmatelives` is a *separate remote* this fork merges from — not this repository.
Links in shipped docs must point at `sdenike/textmate`.

Hard constraints declared by the maintainer:
- arm64 only — do not add x86_64 fallbacks
- System Ruby 2.6.10 only — no bundled Rubies, no downloads, no 1.8 compatibility code
- Forward compatible (macOS 26+); zero traces of Ruby 1.8 anywhere

## Build system

`TextMate.xcodeproj` is the build (Phase 2 replaced `./configure` + `bin/rave` + `ninja`
entirely — there is no other build path). It is generated, committed, and normally does not
need regenerating: `xcodegen generate --spec project.yml` only if `project.yml` itself changes.
`project.yml` is now hand-maintained directly; the `.rave`-reading generator that used to emit
it, `bin/rave2yaml`, was deleted along with the `.rave` files it read.

`xcodebuild -project TextMate.xcodeproj -scheme TextMate -configuration Release build` produces
the app; ⌘B works from inside Xcode too. Dependencies (`boost`, `google-sparsehash`,
`multimarkdown`) are installed via Homebrew and are not checked automatically the way
`./configure` used to check them — `Xcode/Base.xcconfig`'s `HEADER_SEARCH_PATHS` hardcodes
`/opt/homebrew/include`, so a MacPorts prefix does not currently work. `capnp` is **not** a
dependency — Cap'n Proto was removed by the textmatelives merge. `ragel` is also **not** a
dependency: `Frameworks/plist/src/ascii.cc` (formerly `ascii.rl`) is a hand-written ASCII plist
parser, ported from the ragel-generated state machine and verified byte-for-byte against it
across quoting, escaping, and unterminated-input edge cases before the switch.

The compiler config is C++20 (`CLANG_CXX_LANGUAGE_STANDARD = c++20`), ObjC ARC, deployment target
macOS 26.0, all set in `Xcode/Base.xcconfig`. Precompiled headers live in
`Shared/PCH/prelude.{c,cc,m,mm}`. `NULL_STR` is passed via `GCC_PREPROCESSOR_DEFINITIONS`. The
legacy `REST_API` macro (formerly `https://api.textmate.org`) was removed in PR #9; the fork
makes no `api.textmate.org` calls (see "Bundle delivery" below).

Header resolution: each framework's public headers are symlinked into `Xcode/include/<name>/`,
and a target's `HEADER_SEARCH_PATHS` lists only the `Xcode/include/<dep>` roots for frameworks it
actually depends on — this reproduces the old rave build's compiler-enforced dependency isolation
(a target cannot `#include` a framework's headers without declaring a dependency on it). See
`docs/benchmarks/2026-08-12-header-strategy.md` for why this shape was chosen over a flat `-I`.

Common commands:

```sh
bin/setup-hooks                    # ONCE per clone: installs the gitleaks pre-commit hook
bin/build                          # PREFERRED: builds TextMate via xcodebuild
bin/build <Framework>/test         # Build and run a framework's test suite (e.g. scm/test)
bin/build <target>                 # Build any other Xcode target (e.g. mate)
bin/deploy-local                   # Install the built app to /Applications, replacing the prior build

xcodebuild -project TextMate.xcodeproj -scheme TextMate -configuration Release build
```

**Prefer `bin/build` over bare `xcodebuild`.** Two environment problems break Xcode's Ruby-based
script phases (`bin/gen_test`, `bin/gen_html`, `bin/gen_credits.rb` all still shell out to system
Ruby) with errors that point at the wrong culprit, and `bin/build` handles both:

1. Ruby version managers (chruby, rbenv, rvm) export `GEM_HOME`/`GEM_PATH`. The build's helper
   scripts run under system Ruby 2.6 via `#!/usr/bin/env ruby` and then try to dlopen native gems
   built for a different Ruby, failing with `Symbol not found: _rb_cArray (LoadError)`. That reads
   like a broken build; it is a leaked shell environment.
2. `bin/gen_credits.rb` opens a DBM cache at `~/Library/Caches/com.macromates.TextMate/githubcredits.db`.
   If any earlier build ran under `sudo`, that file is root-owned and `DBM.new` fails `EACCES` even
   though the directory is yours. Removing it needs write permission on the directory, not the file,
   so no `sudo` is required to clear it.

Build output goes to `~/build/textmate-revived/xcode` — `SYMROOT`/`OBJROOT`/`SHARED_PRECOMPS_DIR`
are overridden in `Xcode/Base.xcconfig` because xcodebuild otherwise writes a launchable
`TextMate.app` into `<project>/build` inside the working copy, where Spotlight indexes it as a
duplicate.

`bin/deploy-local` **moves** rather than copies: it verifies the installed bundle's
`CFBundleIdentifier` matches what was built, then deletes the build copy, so no launchable
duplicate is left in the build tree. That costs a relink on the next build, not a full rebuild.
It reads `CFBundleIdentifier` from the freshly built app and refuses to replace a
bundle in `/Applications` whose identifier differs — it will not clobber an unrelated TextMate install.

**A `bin/deploy-local` build can never self-update, and that is correct.** Local builds are ad-hoc
signed (`CODE_SIGN_IDENTITY = -` in `Xcode/Base.xcconfig`), so they carry `Signature=adhoc` and
`TeamIdentifier=not set`. `OakDownloadManager` only installs an update whose Developer ID Team
Identifier matches the **running** app's, so Check for Updates downloads the release and then
refuses it with *"The downloaded update is not signed by the expected developer."* That is the
guard working — it is what stops a build signed by someone else replacing yours — not a signing
bug. Confirm which you are running with:

```sh
codesign -dv --verbose=2 /Applications/TextMate.app 2>&1 | grep -E 'Signature|TeamIdentifier'
```

To get a self-updating app, install the real release instead of a local build:

```sh
brew install --cask textmate-revived     # or download the .tbz from Releases
```

Self-hosted building (pressing ⌘B inside a running TextMate.app to rebuild TextMate itself, via
the optional Ninja bundle and `.tm_properties`' old `TM_NINJA_TARGET` mapping) no longer works —
neither ninja nor that mapping exist anymore. Build from Xcode or the command line instead.

## Architecture

Objective-C++. Low-level data structures and parsing are C++; AppKit/Cocoa surfaces are ObjC++ wrapping the C++ types. See `INTERNALS.md` for the buffer/layout/tree internals.

The two largest layers worth knowing:

- **Text core** — `Frameworks/buffer` (`ng::buffer_t`: text storage, lines, scopes, marks), `Frameworks/layout` (`ng::layout_t`: visual layout + drawing), `Frameworks/OakTextView` (`OakTextView`, `GutterView`, `OakDocumentView`). All built on `oak::basic_tree_t`, an AA-tree with binary-indexed offsets.
- **SCM** — Two-tier. `Frameworks/scm` (C++ `scm::shared_info_t`, `scm::info_t`, drivers under `src/drivers/`) does the actual `git status` work behind a per-instance dispatch queue and an FSEvents watcher. `Frameworks/FileBrowser/src/SCMManager.mm` (`SCMRepository`) is the ObjC consumer that subscribes via `info_t::push_callback`. The C++ side is the source of truth — do not reintroduce a parallel ObjC subsystem that re-runs git itself.

`Frameworks/HTMLOutput` was migrated from legacy `WebView` to `WKWebView` for macOS 26. The bundle-output bridge runs through three custom `WKURLSchemeHandler`s (`x-txmt-filehandle`, `tm-file`, `tm-system`) in `Frameworks/HTMLOutput/src/helpers/`. `tm-system` is the synchronous variant required by the git bundle's commit dialog.

## Tests

CxxTest-style, but home-grown: `bin/gen_test` reads each `tests/t_*.{cc,mm}` file, finds top-level `void test_*()` functions, and emits a single runner with `main()`. Assertions are `OAK_ASSERT`, `OAK_ASSERT_EQ`, `OAK_ASSERT_NE`. Filesystem fixtures use `test::jail_t` from `Frameworks/test`.

Each framework's `<name>_test` Xcode target generates its runner via an `Xcode/scripts/gen_test.sh <name>` build-phase script, which itself globs `Frameworks/<name>/tests/t_*.{cc,mm}` (or `vendor/<name>/tests/` for vendor targets like Onigmo) — there is no more `default.rave` `tests` directive declaring that glob per framework. Run via `bin/build <framework>/test`, or `xcodebuild -project TextMate.xcodeproj -target <framework>_test -configuration Release build CODE_SIGNING_ALLOWED=NO` followed by running the produced binary directly.

Runner flags (parsed by the generated runner via `getopt_long`, `bin/gen_test:155-189`):
- `-v` verbose, `-m` measure, `-r N` repeat, `-b` benchmarks, `-p`/`--parallel`, `--no-parallel` (`-P` is not actually wired despite the runner's own usage text — its getopt string is `"bmpr:vhV"`)

**Eight** frameworks' test runners are `.mm` (buffer, document, BundlesManager, FileBrowser, ns, encoding, SoftwareUpdate, and OakAppKit) and call Cocoa APIs that assert `NSThread.isMainThread`; `bin/build` and CI pass `--no-parallel` for exactly those eight. The first seven match what ninja's `RunTest` rule did; `OakAppKit_test` was added 2026-08-14 for the Liquid Glass work and postdates that baseline, so `gen_test.sh`'s own comment still names only seven. **Do not force it universally** — `settings_test`'s `t_track_paths.cc` depends on real wall-clock time passing between filesystem operations across concurrently running tests and reliably fails 1/9 under forced serial execution despite passing under the (parallel) default; found by testing, not assumed.

There is no name-based test filter. To run a subset, either run the test binary directly (`~/build/textmate-revived/xcode/Release/<name>_test -v`) or temporarily edit the test source.

Each `<name>_test` target's **only** source is the runner `gen_test.sh` generates into
`$(DERIVED_FILE_DIR)`; that runner is what pulls in `tests/t_*.{cc,mm}`. Until 2026-08-14 those 28
script phases declared `outputFiles:` and no `inputFiles:`, so Xcode skipped regeneration whenever
the output already existed and never noticed a test file had changed — **adding or editing a test
did nothing while the suite reported green**. Reproduced at the time: appending a test asserting
`false` still gave `** BUILD SUCCEEDED **` and `2 tests passed`. All 28 phases now carry
`basedOnDependencyAnalysis: false`, the same pattern the resource-assembly phases use, so the runner
is regenerated on every test build. If you ever see a test you just wrote pass without running,
check that key first.

`gen_test.sh` then **compares before replacing** — `cmp -s "$out~" "$out"` — and only moves the new
runner into place when its contents differ. Both halves are needed and they fix opposite problems:
the always-run phase stops a changed test being missed, while the comparison stops an unconditional
`mv` bumping the generated file's mtime on every build, which would force a recompile and relink of
every test target every time — a real cost on targets with large dependency lists (`document_test`,
`FileBrowser_test`, `TextMate_test`). Remove either half and you trade one problem for the other.

Tests that shell out to git must call `git init -b master` (not bare `git init`) — modern git's `init.defaultBranch` defaults to `main` and breaks tests that assume `master`.

**`bin/gen_test` wraps each test file in `namespace <filename> { … }`.** Two consequences worth
knowing before they cost you an afternoon. `OAK_ASSERT_EQ` stringifies both operands on failure, so
asserting on a type with no `to_s()` fails to compile — define an overload in the test file, as
`t_OakCompareVersionStrings.mm` does for `NSComparisonResult`. But defining one inside that implicit
namespace **hides the global `to_s` overloads from unqualified lookup**, which breaks unrelated
assertions elsewhere in the same file with a confusing error. Add `using ::to_s;` near the top when
you introduce a local overload.

## Bundle delivery

Only **three** bundles are actually forked. `Frameworks/BundlesManager/src/MandatoryBundles.h` pins
`textmatelives/{bundle-support,text,source}.tmbundle`, each ported to Ruby 2.6.10 — plus
`textmate/themes.tmbundle` at `MandatoryBundles.h:53`, which still points at **upstream**. Every
other bundle comes from `AvailableBundles.plist` (generated by `bin/generate_available_bundles.rb`
into Bundle Support's `Support/` directory) and is fetched stock from wherever that catalogue
names.

`bin/reset_bundles.sh` symlinks `~/src/github.com/textmatelives/bundles/` and
`bundle-support.tmbundle` into `~/Library/Application Support/TextMate/Managed/Bundles/` — but
**those source repositories do not exist on this machine**, so that path is currently inoperative.
The 54 entries in `Managed/Bundles/` are real directories downloaded via codeload, not symlinks.
Do not assume the symlink wiring is in effect; check before relying on it.

The `REST_API` macro and its `api.textmate.org` source were removed in PR #9; bundle delivery is now git-URL/codeload-based (`BundlesManager.mm` fetches via `BundleFetcher` from `codeload.github.com`, `BundleFetcher.mm:65`). `BundlesManager.mm` still polls every 3h via `NSBackgroundActivityScheduler`. Packaging for distribution is unresolved.

### RESOLVED 2026-08-13 — mandatory bundles now come from our own forks

The blocker below is fixed. Four forks were created under `sdenike`, all writable, and
`MandatoryBundles.h` repointed at them:

| Pin | Now | Forked from |
|---|---|---|
| Bundle Support | `sdenike/bundle-support.tmbundle` | textmatelives |
| Text | `sdenike/text.tmbundle` | textmatelives |
| Source | `sdenike/source.tmbundle` | textmatelives |
| Themes | `sdenike/themes.tmbundle` | textmate (upstream) |

Each fork's HEAD sat exactly at the previously pinned SHA, so the only content delta is our own
two commits — no unintended upstream drift came along with the move. **The release no longer
depends on any third-party repository.**

`sdenike/bundle-support.tmbundle` now carries `Support/shared/bin/ruby18`, a shim beside the
existing `ruby` one. It makes all 27 `#!/usr/bin/env ruby18` commands across 13 bundles run,
translating 1.8's `-K` flag to `-EUTF-8` (dropping it is wrong — with `LANG` unset,
`default_external` falls back to US-ASCII and non-ASCII text breaks). **It is a stopgap and the
affected bundles still need forking and porting properly** — several also use `iconv`,
`parsedate`, `Config::CONFIG`, `TimeoutError` and `Object#type`, which no shim can rescue. Read
the shim's own header comment; it says the same thing.

A single `sdenike/textmate-bundles` monorepo was considered and is **not possible** without
rewriting `BundleFetcher`: it parses a bundle URL into owner/repo only, fetches
`codeload.github.com/{owner}/{repo}/tar.gz/{ref}`, and requires `info.plist` at the tarball root.
TextMate is one-bundle-per-repository by design.

`bin/fetch_embedded_bundles.sh` now also scrubs `src/`. Bundle Support ships `find_app.cc` and a
`default.rave` there; the prebuilt `find_app` binary ships separately, so they have no runtime
use, and without the scrub every pin bump silently reintroduced a `.rave` file that `d07cc0c8`
had deleted. (Note for later: that prebuilt `find_app` is a universal x86_64+arm64 binary we did
not build. It is vendored upstream content rather than an x86_64 fallback added to our build, so
it does not breach the arm64-only rule — but now that we own the fork, it could be rebuilt
arm64-only.)

### Historical — the blocker this replaced

`MandatoryBundles.h` pins `textmatelives/{bundle-support,text,source}.tmbundle` as **mandatory**:
bundles the app embeds so a fresh, offline launch still works, and which users cannot remove or
repoint. Verified 2026-08-13 via the GitHub API: this account has **`push=false` and `admin=false`
on all three**, and belongs to no organizations. They are themselves forks (`fork=true`) of the
upstream `textmate/*` bundles.

Consequences, all of which shape the eventual bundle phase:

- Fixes to Bundle Support, Text or Source **cannot be upstreamed**. The embedded copies under
  `Applications/TextMate/support/Bundles/` are generated artifacts (`fetch_embedded_bundles.sh`
  `rm -rf`s and re-copies each from its pinned sha), so any local fix there is discarded the next
  time that pin moves. See the warning comment on the Source pin.
- The `ruby18` compatibility shim that would fix all 27 broken shebangs at once — one file beside
  the existing `ruby` shim in `bundle-support.tmbundle/Support/shared/bin/` — cannot be shipped
  for the same reason.
- `AvailableBundles.plist`, the catalogue of installable bundles, also lives inside
  `Bundle Support.tmbundle/Support/`. So even *hiding* bundles from the installer needs the same
  write access as fixing them; it is not the cheaper option it appears to be.
- The app's offline bootstrap depends on a third party's repositories.

The fix, when the bundle phase starts: re-fork those three under an account we control and
repoint these pins. Until then, treat the embedded copies as read-only generated output.

### KNOWN GAP — bundles are not covered by the Ruby 2.6 constraint

The fork's "zero traces of Ruby 1.8" rule currently stops at the app boundary, and bundles are
where Ruby actually executes. Triaged 2026-08-13 across the 54 installed bundles. Every verdict
below was checked by running the construct against the real system Ruby (2.6.10p210), not
inferred.

**The dominant problem is a shebang, not a language feature.** 24 files across 13 bundles begin
`#!/usr/bin/env ruby18`. There is no `ruby18` on `PATH` and **no `ruby18` shim** in
`bundle-support.tmbundle/Support/shared/bin/` (it ships `ruby` only), so every one of them dies at
`env: ruby18: No such file or directory` before a line of Ruby runs. The `${TM_RUBY:-/usr/bin/ruby}`
shim does not save these — they name a different interpreter.

| Bundle | Broken files | Bundle | Broken files |
|---|---|---|---|
| Java | 4 | Markdown | 1 |
| Python (templates) | 4 | Ruby | 1 |
| YAML | 3 | Source | 1 |
| Active4D | 2 | Groovy | 1 |
| Lua | 2 | HTML | 1 |
| Perl | 2 | Cron | 1 |
| Gist | 1 | | |

The Python entries are `Templates/*/info.plist` whose `<key>command</key>` *is* the `ruby18`
script, so creating a new Python file from a template fails. Two further hits are **not**
breakage: `Ruby.tmbundle/Tests/rubylexer/regtest.rb` is a test fixture, and
`Bundle Development.tmbundle/Snippets/Ruby 1_8 Shebang.tmSnippet` is a snippet whose `<key>content</key>`
inserts a 1.8 shebang — intentional, though a fork that bans 1.8 arguably should not ship a
shortcut for writing one.

**Library and API breakage, separate from the shebangs** (these sets overlap the table above — do
not sum them). Confirmed fatal under 2.6.10: `require 'iconv'` and `require 'parsedate'` both
`cannot load such file` (3 files, 1 file); `Config::CONFIG` and `TimeoutError` both raise
`NameError` (1 file, 3 files); `Object#type` raises `NoMethodError` (~5 files). A `String#each`
pattern matches ~19 files, but that regex also catches `Array#each` and `IO#each`, which are fine
— treat 5 and 19 as upper bounds needing per-file confirmation, not counts.

**Confirmed harmless** — deprecation warning only, code still runs: `Fixnum`/`Bignum` (11 files),
`Hash#index` (18 files). **Confirmed absent entirely**: `$KCODE`, `require 'jcode'`, `ftools`,
`generator`, `soap`. An earlier note in this file claimed `$KCODE` and `jcode` were the real
breakage; that was wrong, and neither appears anywhere in the installed bundles.

Remaining work, **scheduled before Phase 5** because Phase 5 is what makes builds public — a
signed, notarized app that pulls stock 1.8 bundles hands the bug to real users:

1. **Fix the shebangs** — 24 files, 13 bundles. Mechanical, and it is most of the problem.
2. **Fix the library calls** — confirm the `Object#type` and `String#each` hits per file, then port
   `iconv`, `parsedate`, `Config::CONFIG` and `TimeoutError`.
3. **Fork and repoint** — fork whichever bundles get changed, decide the same for
   `themes.tmbundle` (still upstream), point `AvailableBundles.plist` at the forks so a downloaded
   build cannot silently pull stock 1.8 bundles, document an upstream re-merge path, and fix or
   delete `reset_bundles.sh`'s dead paths.

Ruby in bundles resolves through `${TM_RUBY:-/usr/bin/ruby}` via `Support/shared/bin/ruby` in the forked `bundle-support.tmbundle`. `TM_RUBY` is the long-standing override hook — do not introduce a new Ruby discovery scheme.
