# Releasing TextMate Lives

This document describes how releases of the `textmatelives/textmate` fork are
cut today. It reflects `.github/workflows/release.yml`.

## TL;DR

A release is cut by **landing a new top entry in `CHANGELOG.md` on `main`**.
There is no separate "tag" or "publish" step to run by hand — pushing a
`CHANGELOG.md` change to `main` triggers the `Release` workflow, which builds,
signs, notarizes, tags, and publishes the GitHub Release automatically.

## The version is defined in `CHANGELOG.md`

The first `## DATE (vX.Y.Z-undead)` heading at the top of `CHANGELOG.md` is the
single source of truth for the version the release workflow tags, titles, and
writes release notes from (`release.yml:41-52`).

Because the release workflow reads that heading directly, the git tag and
GitHub Release title always match what's at the top of `CHANGELOG.md` at merge
time.

Heading format (matched by `^## .* (v.*)$`):

```
## 2026-05-28 (v2.1.1-undead)
```

The `-undead` suffix is **required** (see the guard below).

## How to cut a release

1. Add a new entry to the **top** of `CHANGELOG.md`, above the previous one:
   `## YYYY-MM-DD (vX.Y.Z-undead)`, followed by `### Section` headings and
   `*` bullets. Reference PRs/issues and commit SHAs (see existing entries).
2. Open a PR from a branch. CI (`ci.yml`) calls the reusable workflow
   `build-and-test.yml`, which runs `build` and `test` as two independent jobs;
   both must pass. It does **not** publish. (The required status checks on
   `main` are `build-and-test / build` and `build-and-test / test`.)
3. Verify the notes render as intended:
   `bin/extract_changes -v X.Y.Z-undead -o - CHANGELOG.md`.
4. Merge the PR to `main`. The push to `main` touching `CHANGELOG.md` triggers
   the `Release` workflow (`release.yml:4-7`).
5. Watch the `Release` run. On success it produces the `vX.Y.Z-undead` tag and a
   public GitHub Release with the `TextMate-X.Y.Z-undead.tbz` asset attached.
6. Confirm an installed older build is offered the update (see "How users get
   it" below).

A run can also be started by hand via **workflow_dispatch** (`release.yml:8`),
but it still reads the version from the current `CHANGELOG.md` top entry.

## What the workflow does (`release.yml`)

The release is a single gated pipeline. A `verify` job runs first; the `release`
job that signs, notarizes, and publishes declares `needs: verify`, so publish
only happens if build **and** test pass.

0. **Verify (fresh build + test gate)** — the `verify` job calls the same
   reusable workflow as CI (`uses: ./.github/workflows/build-and-test.yml`),
   running the `build` and `test` jobs on `macos-26`. The publish job below has
   `needs: verify`, so nothing is signed or released unless both pass.

The `release` job runs on `macos-26`, 60-minute timeout, `contents: write`. It
builds its **own fresh** `xcodebuild ... TextMate` (it does not reuse the
`verify` job's build artifact — the signed/notarized build must be built fresh
in this job):

1. **Extract version** from `CHANGELOG.md` (`:41-52`).
2. **Guard — must be `-undead`** (`:54-68`). If the top version does not contain
   `-undead`, the run skips (no release).
3. **Skip if the tag already exists** on `origin` (`:70-83`). Re-running for an
   already-released version is a no-op.
4. **Install deps** via Homebrew (`:85-87`).
5. **Import the Developer ID certificate** from secrets into an ephemeral
   keychain and resolve the signing identity (`:89-118`).
6. **Build the signed app**: a single `xcodebuild -scheme TextMate -configuration
   Release CODE_SIGN_IDENTITY="$CS_IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp"
   build` (`:120-124`) — hardened runtime comes from `Xcode/Base.xcconfig`'s
   `ENABLE_HARDENED_RUNTIME = YES`, applied unconditionally, not just here.
7. **Locate the built app** at the fixed, xcconfig-pinned
   `~/build/textmate-revived/xcode/Release/TextMate.app` (`:126-140`).
8. **Sign inside-out**: re-sign every embedded Mach-O, re-seal nested bundles,
   then re-sign the outer `.app` with release entitlements
   (`CS_GET_TASK_ALLOW=false`) (`:142-193`), and verify codesign + hardened
   runtime (`:195-201`). Xcode signs the app and its natively-embedded targets
   as part of the build already (verified: `codesign --verify --deep --strict`
   passes on an ad-hoc build straight off `xcodebuild`); this step still
   matters because `Xcode/scripts/assemble_resources.sh` copies some embedded
   binaries with a plain `cp`, which Xcode's own embed-and-sign machinery
   never touches.
9. **Notarize** via `notarytool submit --wait`, parsing the JSON status
   (`--wait` can exit 0 on `Invalid`, so the status is checked explicitly)
   (`:203-232`).
10. **Staple** the ticket (retried until CloudKit propagates) and **verify
    Gatekeeper** with `spctl --assess` (`:234-254`).
11. **Build the `.tbz`** `TextMate-${VERSION}.tbz` (`:256-267`).
12. **Extract release notes** with `bin/extract_changes` (`:269-281`).
13. **Create the GitHub Release** with `gh release create "v${VERSION}"` — no
    `--prerelease`/`--draft`, so it becomes `releases/latest` (`:283-303`).
14. **Delete the ephemeral keychain** (always) (`:305-307`).

## Required GitHub secrets

`release.yml` consumes (the build will fail at signing/notarization without
them):

- `MAC_CERTIFICATE_P12` — base64-encoded Developer ID Application `.p12`.
- `MAC_CERTIFICATE_PWD` — password for that `.p12`.
- `APPLE_ID`, `APPLE_ID_PWD`, `APPLE_TEAM_ID` — notarization credentials
  (`APPLE_ID_PWD` is an app-specific password).

The keychain password is ephemeral (`KEYCHAIN_PWD` = run id), and the certificate
identity is matched by name (`CERT_IDENTITY_NAME` = "Developer ID Application").

## How users get the update

The app checks `api.github.com/repos/textmatelives/textmate/releases/latest`
(`Applications/TextMate/src/AppController.mm:494`), compares the running
`CFBundleShortVersionString` against the release `tag_name`, downloads the first
`.tbz` asset, and installs it only if the downloaded bundle carries a valid
Developer ID Application signature whose Team Identifier matches the **running**
app (`Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm`). It then swaps the bundle
in place and relaunches. A build signed by a different team — or unsigned — is
refused.

## Gotchas

- **Merging a `CHANGELOG.md` change to `main` is the publish action.** There is
  no dry run on `main`; treat the merge as the release.
- **The top entry wins.** Only the first `## ... (vX.Y.Z)` heading is read, so
  the new entry must be above the previous one.
- **`-undead` is mandatory**; a version without it silently skips the release.
- **Tags are immutable here.** To re-release, bump to a new version; the workflow
  will not overwrite an existing tag.
- **A release built without the Developer ID** cannot be consumed by the updater
  (the trust gate requires the same team), so releases must come from the
  signed CI path, not an ad-hoc local build.
