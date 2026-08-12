# Header strategy for the Xcode migration — decided by experiment

Date: 2026-08-12
Decides: Phase 2 Task 3. Tasks 4-7 all depend on this answer.

## The thing being replaced

`ExportHeader` is the largest non-trivial rule in the rave build — **369 edges**, more than
any rule except raw file copying and compilation. It has no native Xcode equivalent, which
made it the single largest risk in Phase 2.

What it actually does, read out of `build.ninja` rather than inferred:

```
rule ExportHeader
  command = /bin/cp -Xp $in $out && touch $out

build $builddir/_Include/authorization/authorization/authorization.h: ExportHeader \
      Frameworks/authorization/src/authorization.h
```

So `Frameworks/<name>/src/x.h` is copied to `_Include/<name>/<name>/x.h`, and each compile
command receives `-I_Include/<dep>` — **only for frameworks the target declares in `require`**.

## The property that is easy to lose

The double nesting (`_Include/<name>/<name>/`) is not incidental. Because a target only gets
`-I_Include/<dep>` for its declared dependencies, and each such directory exposes exactly one
framework's headers under that framework's own name, **a framework's headers are reachable only
by targets that depend on it.**

That is compiler-enforced dependency isolation. The `require` graph in the `.rave` files is not
documentation — it is enforced at build time.

The obvious Xcode shortcut, a single `-I$(SRCROOT)/Frameworks`, would compile and **silently
destroy this**. Every framework could include every other framework's headers, the `require`
graph would stop meaning anything, and nothing would fail to alert us. The damage would only
show up much later as an unpickable dependency tangle.

## Options tested

Test file: `Frameworks/selection/src/selection.cc`, which includes `<buffer/…>`, `<bundles/…>`,
`<crash/…>`, `<regexp/…>`, and `<text/…>` — five genuine cross-framework dependencies.

### Option 1 — flat `-I$(SRCROOT)/Frameworks`: REJECTED

Cannot work at all. Headers live at `Frameworks/<name>/src/x.h`, so `<text/case.h>` would have
to resolve to `Frameworks/text/case.h`, which does not exist. Fails before the isolation
question even arises.

### Option 2 — nesting-preserving symlink farm: **CHOSEN**

Build one directory per framework, each containing a single symlink named after the framework
pointing at that framework's `src`:

```bash
for d in Frameworks/*/; do
  n=$(basename "$d")
  [ -d "$d/src" ] && mkdir -p "$root/$n" && ln -s "$PWD/$d/src" "$root/$n/$n"
done
```

Then grant `-I$root/<dep>` per target, from its `require` list.

**Result — resolution works.** With dependency directories granted, compilation proceeds past
every `<framework/…>` include. The residual failure is `use of undeclared identifier 'NULL_STR'`,
a prefix-header symbol, which is a PCH concern rather than a search-path one.

**Result — isolation is preserved.** Withholding one dependency reproduces exactly the failure
it should:

```
$ # ...same command, but without -I<root>/regexp
Frameworks/selection/src/selection.h:5:10: fatal error: 'regexp/find.h' file not found
```

This is the decisive check. The farm reproduces rave's enforcement rather than merely its
convenience.

### Option 3 — Xcode header maps (`USE_HEADERMAP`): NOT TESTED

Not needed. Option 2 works and is explicit; header maps are implicit and historically
unpredictable across many targets. Explicit beats clever for something 46 targets depend on.

## Decision

Per-framework include directories, generated from each target's `require` list, mirroring
rave's structure. Symlinks rather than copies: 46 directory symlinks instead of 369 file copies,
and no staleness window when a header changes.

`Xcode/Base.xcconfig` carries only the roots common to every target
(`Shared/include`, `/opt/homebrew/include`). The per-framework paths are generated per target by
`bin/rave2yaml` in Task 4.

## Two corrections to the Phase 2 plan, found while doing this

Both were assumptions in the plan that the build itself contradicted.

1. **C++ standard.** The plan specified `CLANG_CXX_LANGUAGE_STANDARD = c++23`. `build.ninja`
   compiles with `-std=c++2a`. Raising the standard across ~92K lines of C++ is a behavioural
   change and does not belong as a silent rider on a build-system migration — it gets its own
   commit with the test suite behind it. The xcconfig uses `c++20` to match reality.

2. **Deployment target.** `build.ninja` still emits `-mmacosx-version-min=10.12`, inherited from
   upstream and surviving the textmatelives merge untouched. Their "macOS 26" applied to release
   packaging, not the compile flag. `Xcode/Base.xcconfig` sets `MACOSX_DEPLOYMENT_TARGET = 26.0`,
   which makes Phase 2 the first point where the compiler is actually told what we target.

   This one is worth watching: code guarded by `@available` or `#if` on older versions may
   behave differently once the deployment target really is 26.0. The test suite is the check.

## Reproducing

```bash
SDK=$(xcrun --show-sdk-path --sdk macosx)
root=/tmp/hdr2 && rm -rf $root && mkdir -p $root
for d in Frameworks/*/; do n=$(basename "$d"); [ -d "$d/src" ] && mkdir -p "$root/$n" && ln -s "$PWD/$d/src" "$root/$n/$n"; done
INC=(); for d in $root/*/; do INC+=("-I${d%/}"); done
xcrun clang++ -std=c++2b -target arm64-apple-macos26.0 -isysroot "$SDK" -fsyntax-only \
  -include Shared/PCH/prelude.cc -IShared/include -I/opt/homebrew/include \
  "${INC[@]}" Frameworks/selection/src/selection.cc
```
