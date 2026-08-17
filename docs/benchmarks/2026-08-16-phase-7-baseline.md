Title: Phase 7 baseline

# Phase 7 baseline — 2026-08-16

Both builds measured on the same machine, in the same session, with
`bin/bench/measure.sh`. Three runs each, no other TextMate process running.

| build | size KB | archs | rpath dylibs | launch ms | RSS MB |
|---|---|---|---|---|---|
| undead | 27928 | arm64 | 0 | 1141 / 1160 / 1110 | 146 |
| revived.23 | 27820 | arm64 | 0 | 813 / 819 / 824 | 136 |

`undead` = TextMate v2.1.4-undead (`textmatelives/textmate`), the pre-fork
lineage this project's gate is defined against. `revived.23` = the published
v3.0.0-revived.23 `.tbz`, expanded — not a local build, which is ad-hoc signed
and which `measure.sh` correctly refuses to launch.

## Result

**Launch ~320 ms (28%) faster, RSS 10 MB lower, size 108 KB smaller.** Two of the
three gate metrics are already met before any optimisation work. Large-file open
is not yet measured.

## Why this document exists rather than a comparison against Phase 0

`docs/benchmarks/2026-08-12-baseline.md` records `undead` at **661 ms**. The same
notarized binary measures **~1137 ms** here today. Nothing about `undead`
changed; the difference is macOS drift over the intervening months, and it is
larger than anything this fork has changed.

Comparing revived.23 against the Phase 0 table gives a 24% launch *regression*.
Measuring both sides today gives a 28% *improvement*. The cross-session
comparison got the sign wrong, not just the magnitude.

**Measure both sides in the same session, or do not compare.**

## Notes for whoever re-runs this

- **A `measure.sh` run that prints a warning is void, whatever number follows.**
  One run here printed its bundle-id skip warning *and* a launch figure of
  1178 ms. The guards are nested such that this should be impossible. The number
  was contention from another TextMate instance; clean runs gave 813/819/824.
- **`undead` timed out three times and then measured fine on retry**, unchanged.
  Possibly first-launch Gatekeeper scanning of a freshly extracted bundle. Kill
  every TextMate process and retry before believing a timeout.
- Both builds ship zero rpath dylibs. The original Phase 7 premise — eliminating
  dylib loads — was already banked before this fork began, which is why the phase
  was re-scoped.

## Where the bytes are

```
Contents/Resources      15460 KB   56% of the bundle
Contents/MacOS           7072 KB
Contents/Library         2332 KB
Contents/SharedSupport   2132 KB
```

The size levers the design document names — dead-strip and LTO tuning — act on
`MacOS`, which is the smaller half. `Resources` is more than double it and has
not been broken down. Do that before tuning link flags.
