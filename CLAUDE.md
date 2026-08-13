# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Fork constraints

This is `textmatelives/textmate`, a fork of `textmate/textmate` targeting macOS 26 / Apple Silicon.

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
`multimarkdown`, `ragel`) are installed via Homebrew and are not checked automatically the way
`./configure` used to check them — `Xcode/Base.xcconfig`'s `HEADER_SEARCH_PATHS` hardcodes
`/opt/homebrew/include`, so a MacPorts prefix does not currently work. `capnp` is **not** a
dependency — Cap'n Proto was removed by the textmatelives merge.

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

Some `.mm` test runners call Cocoa APIs that assert `NSThread.isMainThread` (e.g. `TMFileReference`) and need `--no-parallel`; `bin/build` and CI now pass it for every runner, not just `.mm` ones (always safe — `.cc` runners have no such requirement — and avoids re-deriving `gen_test.sh`'s own per-framework `.cc`/`.mm` classification a third place).

There is no name-based test filter. To run a subset, either run the test binary directly (`~/build/textmate-revived/xcode/Release/<name>_test -v`) or temporarily edit the test source.

Tests that shell out to git must call `git init -b master` (not bare `git init`) — modern git's `init.defaultBranch` defaults to `main` and breaks tests that assume `master`.

## Bundle delivery

The fork uses forked bundles under `~/src/github.com/textmatelives/bundles/` and `bundle-support.tmbundle`, ported to Ruby 2.6.10. Local dev wires them in via symlinks in `~/Library/Application Support/TextMate/Managed/Bundles/` — `bin/reset_bundles.sh` performs that wiring.

The `REST_API` macro and its `api.textmate.org` source were removed in PR #9; bundle delivery is now git-URL/codeload-based (`BundlesManager.mm` fetches via `BundleFetcher` from `codeload.github.com`). `BundlesManager.mm` still polls every 3h via `NSBackgroundActivityScheduler`. The Managed/Bundles symlink approach side-steps this for development; packaging for distribution is unresolved.

Ruby in bundles resolves through `${TM_RUBY:-/usr/bin/ruby}` via `Support/shared/bin/ruby` in the forked `bundle-support.tmbundle`. `TM_RUBY` is the long-standing override hook — do not introduce a new Ruby discovery scheme.
