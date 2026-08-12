# Build attempt — 2026-08-12

**The 2021 tree does not build on the current toolchain. `./configure` fails on a clean
checkout, and once that failure is worked around, `ninja TextMate` also fails.** Phase 0
does not yield a working regression oracle. See "Consequence" below.

Environment: macOS 26.6.1 (25G76), Xcode 26.6 (17F113), Apple clang version 21.0.0
(clang-2100.1.1.101), target `arm64-apple-darwin25.6.0`. Tree targets `APP_MIN_OS = 10.12`,
last touched 2021-10-12 (`346b52b1`) — five clang major versions behind what compiled it.

## Dependencies (all pre-installed via Homebrew, none installed/upgraded/downgraded by this task)

| dependency | installed version |
|---|---|
| boost | 1.90.0_1 |
| capnp | 1.5.0 |
| google-sparsehash | 2.0.4 |
| multimarkdown | 6.8.0 |
| ninja | 1.13.2 |
| ragel | 6.11 |

`capnp` 1.5.0 is current-day Cap'n Proto; the tree was written against a 2021-era release.
That gap is a plausible independent source of breakage on top of the clang gap, though it
was never reached in this attempt — the build never got past a missing-header error for
`boost`, so `capnp`'s C++ API compatibility was not exercised.

## `git submodule update --init --recursive`

Succeeded. All 6 submodules (`bin/CxxTest`, `Applications/TextMate/icons`,
`Applications/SyntaxMate/resources/SyntaxMate.tmBundle`, `PlugIns/dialog`,
`PlugIns/dialog-1.x`, `vendor/Onigmo/vendor`, `vendor/kvdb/vendor`) cloned and checked out
at the commits the superproject already pinned. Not in question; recorded for completeness.

## `./configure`: fails on a clean checkout

First invocation, full log in `/tmp/configure.log`, exit 1:

```
*** dependency missing: '/usr/local/include/boost/crc.hpp'. Install dependency and/or update 'local.rave' with correct path.
```

Root cause: `configure` hardcodes `/usr/local/include` and `/usr/local/lib` as the only
place it looks for `boost`, `capnp`, and `sparsehash` headers/libs (`configure:19-25`).
Homebrew on Apple Silicon installs to `/opt/homebrew`, not `/usr/local` — confirmed via
`brew --prefix boost` → `/opt/homebrew/opt/boost`. `/usr/local/include` exists on this
machine but holds unrelated tooling (a Node install), not `boost`/`capnp`/`sparsehash`. All
three dependencies are genuinely installed (table above); `configure` simply never looks in
the place Homebrew actually put them. This predates the clang question entirely — it is a
build-tooling assumption from the Intel-Homebrew era (`/usr/local` was the default prefix
there) that has not been updated for Apple Silicon's `/opt/homebrew`.

**A second finding, in `configure` itself:** the failing branch writes `local.rave`'s first
two lines (`add FLAGS "-I/usr/local/include"`, `add LN_FLAGS "-L/usr/local/lib"`) via
`echo >>` *before* it validates that the headers exist (`configure:15-25`). So the failed
first run still leaves a `local.rave` behind. A second, completely unmodified invocation of
`./configure` sees that file, prints "Skipping writing 'local.rave': File already exists",
skips the entire dependency-validation block, and exits 0 — generating `build.ninja`
without ever having actually confirmed `boost`/`capnp`/`sparsehash` are reachable. A
developer who reruns `configure` after seeing the error (a natural reaction) gets a false
green light. This was reproduced twice, unmodified, no hand edits to `local.rave`'s content.

## `ninja TextMate`: fails

Two full runs; log for the reported one is `/tmp/build.log`. Both completed in ~2 seconds —
nowhere near the 20-minute time-box.

**Methodology note:** the first attempt failed with `error: unable to open output file
'.../euc_jp.o': 'Operation not permitted'` against the default build directory
(`~/build/textmate/release`). That directory contained a `_CompileClang` subtree owned by
`root`, timestamped the day before this session (unrelated prior activity on this machine,
not created by this task) — a filesystem permission artifact, not a compiler finding. It was
worked around by pointing `bin/rave` at a clean, session-scoped build directory via
`configure`'s own pre-existing `$builddir` environment variable (`configure:32-34`,
unmodified), rather than by touching the stale directory or any tracked file. The reported
run below is the one against the clean build directory.

Of 853 planned targets, ninja dispatched 239 before stopping (default `-k1`: stop after the
first failure, let already-dispatched parallel jobs finish). 3 steps failed. First 3 distinct
errors found (fewer than 5 — see note below):

1. **(configure-time, above)** `dependency missing: '/usr/local/include/boost/crc.hpp'`
2. `Shared/PCH/prelude.cc:24:10: fatal error: 'boost/crc.hpp' file not found` — same root
   cause as #1, now confirmed at actual compile time: no include path anywhere in
   `default.rave`/`local.rave` reaches `/opt/homebrew`, so the compiler genuinely cannot see
   `boost`. `prelude.cc`/`prelude.mm` are the shared precompiled header nearly every C++/
   ObjC++ translation unit in the tree includes, so this one miss blocks the great majority
   of the 853 targets transitively — the build stopping at 239/853 is a consequence of this,
   not 614 independent problems.
3. Generating `Applications/TextMate/about/Contributions.html` (via `bin/gen_credits.rb`)
   crashed with a Ruby `LoadError`: `dlopen(.../openssl-4.0.2/lib/openssl.bundle...): Symbol
   not found: _rb_cArray`. The system Ruby (2.6, `/System/Library/Frameworks/Ruby.framework`)
   is loading the `openssl` gem from a different, non-system Ruby (3.3.6, under
   `~/.rubies/`) on this machine's `$GEM_PATH`. Unrelated to clang/C++; a Ruby
   version-manager mismatch, and a genuinely distinct failure from #1/#2.

Only 3 distinct errors were reachable, not 5, because the `boost` miss (#2) transitively
blocks nearly everything downstream via the shared PCH — there was no path to more distinct
errors without patching `local.rave`'s include paths, which is explicitly out of scope for
this task.

## Consequence

The 86 inherited CxxTest suites cannot serve as the regression oracle until Phase 1.
`textmatelives/main` has working CI (`build-and-test.yml`) and ships releases, so its tree
builds and tests today. Phase 1's gate therefore becomes "textmatelives' suites pass on our
merged tree", and Phase 0's role is reduced to hygiene, remotes, and the binary-level
baseline.

## Not run

Because the build did not succeed, no test suite was run (`ninja` full target, `ninja
<framework>`) and no "tests ran / passed" count exists to report.
