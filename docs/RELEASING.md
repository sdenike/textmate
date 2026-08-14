# Releasing TextMate Revived

This document describes how releases of the `sdenike/textmate` fork are
cut today. It reflects `.github/workflows/release.yml`.

## TL;DR

A release is cut by **landing a new top entry in `CHANGELOG.md` on `master`**.
There is no separate "tag" or "publish" step to run by hand — pushing a
`CHANGELOG.md` change to `master` triggers the `Release` workflow, which builds,
signs, notarizes, tags, and publishes the GitHub Release automatically.

## The version is defined in `CHANGELOG.md`

The first `## DATE (vX.Y.Z-revived)` heading at the top of `CHANGELOG.md` is the
single source of truth for the version the release workflow tags, titles, and
writes release notes from (`release.yml:41-52`).

Because the release workflow reads that heading directly, the git tag and
GitHub Release title always match what's at the top of `CHANGELOG.md` at merge
time.

Heading format (matched by `^## .* (v.*)$`):

```
## 2026-05-28 (v2.1.1-revived)
```

The `-revived` suffix is **required** (see the guard below).

## How to cut a release

1. Add a new entry to the **top** of `CHANGELOG.md`, above the previous one:
   `## YYYY-MM-DD (vX.Y.Z-revived)`, followed by `### Section` headings and
   `*` bullets. Reference PRs/issues and commit SHAs (see existing entries).
2. Open a PR from a branch. CI (`ci.yml`) calls the reusable workflow
   `build-and-test.yml`, which runs `build` and `test` as two independent jobs;
   both must pass. It does **not** publish. (The required status checks on
   `master` are `build-and-test / build` and `build-and-test / test`.)
3. Verify the notes render as intended:
   `bin/extract_changes -v X.Y.Z-revived -o - CHANGELOG.md`.
4. Merge the PR to `master`. The push to `master` touching `CHANGELOG.md` triggers
   the `Release` workflow (`release.yml:4-7`).
5. Watch the `Release` run. On success it produces the `vX.Y.Z-revived` tag and a
   public GitHub Release with the `TextMate-X.Y.Z-revived.tbz` asset attached.
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
2. **Guard — must be `-revived`** (`:54-68`). If the top version does not contain
   `-revived`, the run skips (no release).
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

## First-time setup (not yet done)

**No release has ever been cut from this repository.** As of 2026-08-13
`gh api repos/sdenike/textmate/actions/secrets` returns `total_count: 0`, and
the `Release` workflow has never run. Until the five secrets below exist, a
release run reaches the signing step and fails.

### 1. Export the Developer ID certificate as a `.p12`

There is no `.p12` on disk; the signing identity lives in the login keychain
(`security find-identity -v -p codesigning` shows
`Developer ID Application: Shelby DeNike (485WH9DHS4)`). A `.p12` is how that
identity gets into CI, so it has to be exported once.

In **Keychain Access**, find the *Developer ID Application* certificate, expand
it so the **private key is included in the selection**, right-click → Export,
save as `.p12`, and set a strong password — that password becomes
`MAC_CERTIFICATE_PWD`. Exporting the certificate without its private key
produces a `.p12` that cannot sign.

### 2. Create an app-specific password

`APPLE_ID_PWD` must be an **app-specific password** from
<https://appleid.apple.com> → Sign-In and Security → App-Specific Passwords —
not the Apple ID password itself.

The `AuthKey_*.p8` files under `~/.appstoreconnect/private_keys/` are App Store
Connect API keys. `notarytool` *can* authenticate with those instead
(`--key`/`--key-id`/`--issuer`), but this workflow is written for the Apple ID
plus app-specific-password form. Do not substitute one for the other without
changing `release.yml`.

### 3. Set the secrets

```sh
base64 -i /path/to/developer-id.p12 | gh secret set MAC_CERTIFICATE_P12 --repo sdenike/textmate
gh secret set MAC_CERTIFICATE_PWD --repo sdenike/textmate   # the .p12 export password
gh secret set APPLE_ID            --repo sdenike/textmate   # Apple ID email
gh secret set APPLE_ID_PWD        --repo sdenike/textmate   # app-specific password from step 2
gh secret set APPLE_TEAM_ID       --repo sdenike/textmate   # 485WH9DHS4
```

If `gh` refuses on permissions — the fine-grained PAT in use cannot even create
pull requests — use the web UI: Settings → Secrets and variables → Actions.

### 4. Delete the exported `.p12`

Once the secret is set, remove the file. It is the signing identity in portable
form, and it is no longer needed locally.

### 5. Dry-run before trusting it

Trigger the workflow by hand (`workflow_dispatch`) rather than discovering
problems during a real release. It still reads the version from the top of
`CHANGELOG.md`, and it will skip cleanly if the tag already exists.

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

The app does **not** poll the GitHub Releases API. It fetches git's smart-HTTP
ref advertisement —
`https://github.com/sdenike/textmate.git/info/refs?service=git-upload-pack`,
what `git ls-remote` reads — set in `Applications/TextMate/src/AppController.mm`.
That endpoint is unmetered, so update checks cannot be starved by
`api.github.com`'s 60-requests-per-hour-per-IP quota.

From that advertisement `SoftwareUpdate` picks the highest `refs/tags/v*`
version (the beta channel includes `-beta` tags; the others skip them, so beta
users converge back onto stable once it catches up) and *derives* the asset URL
from the same host and path rather than querying for it:
`https://github.com/sdenike/textmate/releases/download/vX.Y.Z/TextMate-X.Y.Z.tbz`
(`OakUpdateAssetURLForVersion`). That is why the feed URL and `release.yml`'s
asset naming must stay in step — the updater assumes the convention.

The download installs only if the extracted bundle carries a valid Developer ID
Application signature whose Team Identifier matches the **running** app
(`Frameworks/SoftwareUpdate/src/OakDownloadManager.mm`). It then swaps the
bundle in place and relaunches. A build signed by a different team — or
unsigned — is refused.

**This is why the feed URL matters.** Until 2026-08-13 it pointed at
`textmatelives/textmate`, so this fork's users would have been offered a
different project's builds. The Team Identifier check meant those would have
been rejected rather than installed, but updates could never have succeeded.

## Gotchas

- **Merging a `CHANGELOG.md` change to `master` is the publish action.** There is
  no dry run on `master`; treat the merge as the release.
- **The top entry wins.** Only the first `## ... (vX.Y.Z)` heading is read, so
  the new entry must be above the previous one.
- **`-revived` is mandatory**; a version without it silently skips the release.
- **Tags are immutable here.** To re-release, bump to a new version; the workflow
  will not overwrite an existing tag.
- **A release built without the Developer ID** cannot be consumed by the updater
  (the trust gate requires the same team), so releases must come from the
  signed CI path, not an ad-hoc local build.
