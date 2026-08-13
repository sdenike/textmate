# TextMate Revived — Phase 3: Dependency Purge

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Zero Homebrew dependencies to build. Remove `boost`, `sparsehash`, and `ragel`; replace the hand-rolled `network` framework with `URLSession`; decide the fate of `crash`/`CrashReporter`.

**Architecture:** Mostly mechanical, and far smaller than originally scoped. Recon measured the real footprint rather than assuming it. Where `tectiv3` (PR #1467) already solved a removal, harvest their approach rather than re-deriving it.

**Tech Stack:** Xcode 26.6, C++20, `std::variant`, `std::unordered_map`, zlib, `URLSession`.

## Global Constraints

- Apple Silicon only, `ARCHS = arm64`.
- Repository `sdenike/textmate` is PUBLIC and GPLv3. No credentials in any commit, ever.
- Every CI job keeps `if: github.repository == 'sdenike/textmate'`.
- `CFBundleIdentifier` stays `com.macromates.TextMate`; `CFBundleName` stays `TextMate`. The identifier change is Phase 4.
- Root `CHANGELOG.md` remains the single source of `APP_VERSION`.
- After each task: build, bump the version, update the changelog, deploy, and verify.
- `STREAM.md` entry in the same commit as its change. Conventional-commit prefixes.
- **All 26 test targets must keep passing**, matching `docs/benchmarks/2026-08-12-ninja-parity.md`. That document is the regression oracle now that ninja is gone.

## Measured footprint

| Dependency | Real usage | Source |
|---|---|---|
| `boost` | **2 lines** — `boost/crc.hpp`, `boost/variant.hpp` at `Shared/PCH/prelude.cc:2-3` | recon |
| `sparsehash` | **1 line** — `dense_hash_map` at `prelude.cc:4` | recon |
| `ragel` | **1 file** — `Frameworks/plist/src/ascii.rl` (191 lines) → `$(DERIVED_FILE_DIR)/_Rplist_ascii.cc` at build time | recon |
| `multimarkdown` | **zero references — already gone** | recon |
| `Frameworks/network` | 1236 lines, 11 headers, **zero includes from outside the framework** | recon |
| `crash` + `CrashReporter` | 404 lines; 4 external includers (`io/src/exec.cc:6`, `layout/src/ct.cc:7`, `layout/src/layout.cc:12`, `selection/src/selection.cc:11`) | recon |

Only `/opt/homebrew/include` remains on `HEADER_SEARCH_PATHS` (`Xcode/Base.xcconfig:80`), serving boost and sparsehash. Remove those two and the header path goes with them.

## Harvest, don't re-derive

`tectiv3/develop` solved four of these in an 8-hour window, after their CMake migration had already landed, so the removals are **not tangled with CMake** and are mechanical:

| Dep | Their approach | Commit |
|---|---|---|
| boost | `std::variant` + zlib `crc32()` | `2c49eead` |
| sparsehash | `std::unordered_map` | `36acd469` |
| ragel | hand-written ASCII plist parser; `.rl` deleted, `ascii.cc` replaces it | `34e166b9` |
| multimarkdown | pre-generated HTML committed | `4aa342a9` (N/A — already gone here) |
| `network` | **removed entirely, along with the updater** | `a85e40af` |
| `CrashReporter` | removed outright | `025f2ef8` |

**Their tree is upstream-based; ours is textmatelives-based with 231 commits of divergence.** Cherry-picks may not apply cleanly. Use their approach as the design, and port by hand where the patch conflicts.

## The one place we must diverge from tectiv3

They deleted `network` **and** the software updater together. **We keep the updater** — textmatelives' GitHub-Releases updater is what Phase 5 builds on, and it is a stated project goal.

So for us `network` is a **replacement**, not a deletion. Whatever `SoftwareUpdate` needs — download, signature verification, tbz extraction — must keep working on `URLSession`. Deleting `network` outright would silently remove in-app updates.

---

### Task 1: Remove boost and sparsehash

**Files:** `Shared/PCH/prelude.cc`, plus every use of the affected types. `Xcode/Base.xcconfig`.

- [ ] **Step 1:** Find every use of `boost::crc_32_type`, `boost::variant`, and `dense_hash_map` in the tree (excluding `vendor/`). The includes are in the prelude, so uses are scattered — enumerate them before changing anything.
- [ ] **Step 2:** Replace `boost::variant` with `std::variant`. Note the visitation syntax differs: `boost::apply_visitor` becomes `std::visit`, and `boost::get<T>` becomes `std::get<T>`. This is where subtle breakage hides — the compiler catches most of it, tests catch the rest.
- [ ] **Step 3:** Replace `boost::crc_32_type` with zlib's `crc32()` (`#include <zlib.h>`, already on the system, link `libz`). **Verify byte-for-byte** that the new CRC produces identical values for the same input — a silently different checksum would corrupt any persisted data keyed on it. Write a probe comparing both implementations over a fixed set of inputs before deleting the old one.
- [ ] **Step 4:** Replace `dense_hash_map` with `std::unordered_map`. `dense_hash_map` requires `set_empty_key()`; `std::unordered_map` does not, so remove those calls. Watch for code depending on `dense_hash_map`'s iteration order — it has none guaranteed, but neither does `unordered_map`, so behaviour changes are possible where code accidentally relied on it.
- [ ] **Step 5:** Remove `/opt/homebrew/include` from `HEADER_SEARCH_PATHS` if nothing else needs it.
- [ ] **Step 6:** Build; run all 26 test targets; compare against the parity document.
- [ ] **Step 7:** Commit.

### Task 2: Remove ragel

**Files:** `Frameworks/plist/src/ascii.rl`, `Xcode/scripts/gen_ragel.sh`, `project.yml`.

Two viable approaches — decide by inspection, and record why:

**(a) Commit the generated output.** Run ragel once, commit `ascii.cc`, delete the `.rl` and the script phase. Cheapest, zero behaviour risk, but the generated file becomes the source of truth and nobody can regenerate it without reinstalling ragel.

**(b) Port tectiv3's hand-written parser** (`34e166b9`). Readable and maintainable, but it is a real parser rewrite and plist parsing is load-bearing — every bundle, theme, and settings file goes through it.

- [ ] **Step 1:** Read tectiv3's `34e166b9` to see how large and how faithful their hand-written parser is.
- [ ] **Step 2:** Decide, and record the reasoning in the commit message.
- [ ] **Step 3:** Whichever path — the `plist` test suite is the gate. It must pass unchanged. If choosing (b), also parse a real bundle's `info.plist` and a theme and compare output against the current parser before switching.
- [ ] **Step 4:** Remove the ragel script phase and its `project.yml` wiring.
- [ ] **Step 5:** Build, test, commit.

### Task 3: Replace `network` with URLSession

**Files:** `Frameworks/network/*`, `Frameworks/SoftwareUpdate/*`, `project.yml`.

The framework has **zero external includes** — only `SoftwareUpdate` and `network_test` depend on the target. That makes this a contained swap rather than a sprawl.

- [ ] **Step 1:** Enumerate exactly what `SoftwareUpdate` uses from `network`. The 11 headers cover download, tbz extraction, signature verification, proxy, keychain, and user-agent — but `SoftwareUpdate` may use only a subset. Only what is actually used needs replacing.
- [ ] **Step 2:** **Do not delete the updater.** tectiv3 removed `network` and the updater together; we keep the updater. Confirm in-app updates still function after the swap.
- [ ] **Step 3:** Implement the replacements on `URLSession`. Signature verification and keychain access are security-relevant — they get reviewed in the main loop, not delegated.
- [ ] **Step 4:** Port `network`'s tests to cover the replacements. Deleting a framework and its tests together would remove the evidence that the replacement works.
- [ ] **Step 5:** Delete `Frameworks/network` once nothing references it.
- [ ] **Step 6:** Build, test, commit.

### Task 4: Decide `crash` / `CrashReporter`

404 lines, 4 external includers. textmatelives kept them; tectiv3 deleted them.

- [ ] **Step 1:** Determine what the 4 includers actually use — if it is only an assertion or logging macro, the removal is trivial; if it installs signal handlers, removal changes crash behaviour.
- [ ] **Step 2:** Decide: keep, delete, or replace with macOS's own crash reporting. Record the reasoning. **Note the app currently has no crash reporting endpoint** — `api.textmate.org` is gone — so an enabled reporter that posts nowhere is dead weight, while `crash`'s local assertion helpers may still be useful.
- [ ] **Step 3:** Implement, build, test, commit.

---

## Phase 3 Exit Criteria

- [ ] `brew list` is not consulted by any build step; a machine with no Homebrew packages can build the app.
- [ ] `/opt/homebrew/include` no longer appears in `HEADER_SEARCH_PATHS`.
- [ ] No `#include <boost/`, `<sparsehash/`, or `.rl` file remains outside `vendor/`.
- [ ] In-app software update still works — the updater was not collateral damage.
- [ ] All 26 test targets pass, matching `docs/benchmarks/2026-08-12-ninja-parity.md`.
- [ ] A release is built, versioned, changelogged, and deployed.

## Risks

| Risk | Mitigation |
|---|---|
| zlib CRC differs from boost's, silently corrupting persisted data | Task 1 Step 3 requires a byte-for-byte comparison probe before the old code is deleted |
| Hand-written plist parser diverges from the ragel grammar | Task 2 gates on the `plist` suite plus real bundle/theme parsing |
| Deleting `network` takes the updater with it | Task 3 Step 2 makes keeping the updater an explicit gate |
| `std::variant` visitation differs subtly from `boost::variant` | Compiler catches most; the 26 test targets catch the rest |
