# TextMate Revived — Phase 4: Identity

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Change the application's identity to `com.shelbydenike.*` without orphaning a single piece of the user's existing state.

**Architecture:** The `com.macromates.*` strings in this tree are not one thing. Some are *identity* (change them), some are *data format written into the user's own files* (changing them destroys user data), and some are internal chrome (leave them alone). The entire phase turns on telling these apart.

**Tech Stack:** Xcode 26.6, `NSUserDefaults`, extended attributes, `SMJobBless`/launchd, UTIs.

## Global Constraints

- Apple Silicon only. Repository is PUBLIC and GPLv3. No credentials in any commit, ever.
- Every CI job keeps `if: github.repository == 'sdenike/textmate'`.
- `CFBundleName` stays **`TextMate`** — the user asked that the menu bar not read "TextMate Revived". The version string (`3.0.0-revived.N`) is what identifies this build.
- Root `CHANGELOG.md` remains the single source of `APP_VERSION`.
- After each task: build, bump version, update changelog, deploy, verify.
- All 25 test targets must keep matching `docs/benchmarks/2026-08-12-ninja-parity.md`.
- `STREAM.md` entry in the same commit. Conventional-commit prefixes.

## The classification — this is the whole phase

### CHANGE — identity

| What | Where | Note |
|---|---|---|
| `CFBundleIdentifier`, app | `Applications/TextMate/Info.plist:12` (template `com.macromates.${TARGET_NAME}`) | → `com.shelbydenike.${TARGET_NAME}` |
| `CFBundleIdentifier`, QuickLookGenerator | `Applications/QuickLookGenerator/Info.plist:12` | same template |
| `CFBundleIdentifier`, Dialog / Dialog2 | `PlugIns/*/Info.plist:16` (`com.macromates.plugin.${TARGET_NAME}`) | → `com.shelbydenike.plugin.*` |
| Cache directory | `gtm.cc:104`, `generate.mm:38`, `BundlesManager.mm:950,957`, `bin/gen_credits.rb:202`, `bin/build:16,30` | `~/Library/Caches/com.macromates.TextMate/` — 6 references |
| App bundle lookup | `mate.mm:59`, `gtm.cc:104` | `URLForApplicationWithBundleIdentifier:` |
| Privileged helper | `Applications/PrivilegedTool/src/constants.h:4-8` | job name, tool path, socket, LaunchDaemon plist, authorization right — 5 identifiers |
| QuickLook prefs suite | `QuickLookGenerator/src/generate.mm:209` | explicit suite name `@"com.macromates.TextMate"` |

### DO NOT CHANGE — data format written into user files or consumed by third parties

**Changing any of these destroys user data or breaks interoperability. They are not identity; they are on-disk format.**

| What | Where | Why it must not change |
|---|---|---|
| Extended attributes | `OakDocument.mm` — `com.macromates.bookmarks`, `.folded`, `.crc32`, `.selectionRange`, `.visibleIndex`, `.backup.*` | Written onto **the user's own documents**. Renaming them orphans every bookmark and code fold on every file ever opened, silently. |
| UTIs | `Applications/TextMate/Info.plist` — 38 `com.macromates.textmate.*` declarations | Identify document types system-wide and inside every installed bundle's `info.plist`. Renaming breaks bundle/document associations. |
| `txmt://` URL scheme | `Info.plist` `CFBundleURLSchemes` | Used by external tools, documentation, and existing links across the internet. |
| Authorization right string | `constants.h` `com.macromates.textmate.openfile` | **Evaluate in Task 3** — it is stored in the system authorization database. May need to change with the helper, or may be safe to keep. |

### LEAVE ALONE — internal chrome, no user-visible effect

Dispatch queue and log-subsystem names (`com.macromates.metadata`, `com.macromates.JavaScript`), error domain (`OakCommand.mm:25`), pasteboard type (`OakTabBarView.mm:26`), Touch Bar identifiers (`OakTextView.mm:3007-3009`), Mach port names for Dialog and the commit window. Renaming these is churn with risk and no benefit. If a later phase has a reason, it can revisit.

### Survives untouched

`~/Library/Application Support/TextMate` is the **literal string** `TextMate`, not derived from the identifier (`main.mm:51`, `AppController.mm:505`, `tm_query.cc:32`, `generate.mm:30`). Bundles, themes, and gems are therefore unaffected. This is the single biggest piece of user state and it needs no migration.

---

### Task 1: Migrate preferences before changing anything

**Files:** new migration source under `Applications/TextMate/src/`, plus its test.

`NSUserDefaults.standardUserDefaults` is implicitly keyed on `CFBundleIdentifier`. The moment the identifier changes, every setting the user has — themes, font, window layout, file browser state, everything — silently reverts to defaults. The app will look freshly installed.

**Write the migration first, and land it in a release BEFORE the identifier changes.** A migration that ships in the same build as the rename has never run against the old domain on a real machine.

- [ ] **Step 1: Write the failing test.** Given a populated `com.macromates.TextMate` defaults domain and an empty `com.shelbydenike.TextMate`, migration copies every key. Given a non-empty destination, it does nothing (never clobber newer settings).
- [ ] **Step 2:** Run it, confirm it fails.
- [ ] **Step 3:** Implement. Read the old domain via `NSUserDefaults(suiteName:)`, copy keys the destination lacks, set a `MigratedFromMacromates` marker so it runs exactly once. **Do not delete the old domain** — leaving it intact means an install can be rolled back, and costs a few kilobytes.
- [ ] **Step 4:** Run the test; verify it passes.
- [ ] **Step 5:** Test against a real defaults domain: back up `~/Library/Preferences/com.macromates.TextMate.plist`, run, compare key-for-key.
- [ ] **Step 6:** Commit.

### Task 2: Change the bundle identifiers

**Files:** `Applications/TextMate/Info.plist`, `Applications/QuickLookGenerator/Info.plist`, `PlugIns/*/Info.plist`, `project.yml`.

- [ ] **Step 1:** Change the identifier templates to `com.shelbydenike.*`. **Do not touch the 38 UTI declarations or the `txmt://` scheme** in the same file — they are in the DO NOT CHANGE table above and share the file.
- [ ] **Step 2:** Update the 6 hardcoded cache paths and the QuickLook explicit prefs suite.
- [ ] **Step 3:** Update `mate.mm:59` and `gtm.cc:104` bundle lookups. **`mate` finding the wrong app — or no app — is the most user-visible way this breaks**, so verify `mate` opens a file in the running app after the change.
- [ ] **Step 4:** Build, deploy, and verify the migration from Task 1 actually fires: settings carry over, not reset.
- [ ] **Step 5:** Verify `bin/deploy-local`'s identifier guard still behaves — it compares built vs installed, so the first install after the rename will see a mismatch. **This is expected and correct**; it is the guard doing its job. Handle it deliberately (move the old app aside once), and record what happened.
- [ ] **Step 6:** Commit.

### Task 3: The privileged helper

**Files:** `Applications/PrivilegedTool/src/constants.h`, plus its installation path.

The helper registers with launchd under `com.macromates.auth_server`, installs to `/Library/PrivilegedHelperTools/`, and declares an authorization right. Privileged helpers are registered **by identifier**, and a stale registration from the old identifier will linger in `/Library/LaunchDaemons/`.

- [ ] **Step 1:** Determine what the helper is actually used for and whether it is reachable in normal use. If it is effectively dead — as `CrashReporter` was — deleting it is better than renaming it. Establish this with evidence before doing either.
- [ ] **Step 2:** If keeping: change the five identifiers, and handle the **old registration**. A previously-installed `com.macromates.auth_server` daemon does not disappear because we renamed ours. Decide whether to leave it, or unload and remove it, and record why. Removing another app's daemon would be wrong; removing our own predecessor's is housekeeping.
- [ ] **Step 3:** Evaluate the authorization right string. It lives in the system authorization database, so renaming creates a new right the user must re-approve.
- [ ] **Step 4:** Build, test, commit.

### Task 4: Attribution and credits

**Files:** `README.md`, `Legal.md`, About window resources, `bin/gen_credits.rb`.

- [ ] **Step 1:** README states plainly that this is an unaffiliated community fork of TextMate by MacroMates, under GPLv3. This is both a licence obligation and honest.
- [ ] **Step 2:** Preserve MacroMates' copyright notices. Add ours alongside, not instead.
- [ ] **Step 3:** `Legal.md` still credits boost — removed in Phase 3. Audit it against what the app actually bundles now.
- [ ] **Step 4:** Commit.

---

## Phase 4 Exit Criteria

- [ ] `CFBundleIdentifier` is `com.shelbydenike.TextMate`; helpers and plug-ins likewise.
- [ ] An existing install's **settings carry over** — verified on a real machine, not just in tests.
- [ ] Bookmarks and code folds on existing files still work (xattrs unchanged).
- [ ] Existing bundles still load and their document types still associate (UTIs unchanged).
- [ ] `txmt://` links still open.
- [ ] `mate` opens files in the running app.
- [ ] All 25 test targets match the parity document.
- [ ] A release is built, versioned, changelogged, deployed.

## Risks

| Risk | Mitigation |
|---|---|
| Renaming xattrs orphans every bookmark and fold | Explicitly in the DO NOT CHANGE table; Task 2 Step 1 calls it out because they share a file with things that do change |
| Renaming UTIs breaks bundle document associations | Same table; same warning |
| Settings silently reset on first launch after rename | Task 1 ships the migration in a release *before* the rename |
| `mate` can no longer find the app | Task 2 Step 3 verifies explicitly |
| Stale privileged helper left registered under the old identifier | Task 3 Step 2 handles it deliberately |
| `deploy-local`'s guard blocks the first post-rename install | Expected; Task 2 Step 5 handles it as designed behaviour, not a bug |
