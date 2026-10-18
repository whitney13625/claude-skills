---
name: bootstrap-xcode-project
description: Scaffold a new iOS Xcode project via XcodeGen — .xcodeproj, Swift Testing + XCUITest targets, MVVM folders, optional SwiftData/CoreData/GRDB, SwiftLint, private GitHub repo (in your configured GitHub organization by default), GitHub Actions CI via the xcode-ci skill. Triggers on "bootstrap xcode", "new iOS project", "建一個新的 Xcode project", or any request to start a fresh iOS app from scratch.
---

# Bootstrap Xcode Project

Scaffold a new iOS app project end-to-end. The generated project must satisfy:

1. Contains a real `.xcodeproj` (generated via XcodeGen from a `project.yml`).
2. Includes a unit test target folder (`{ProjectName}Tests/`) using **Swift Testing**.
3. Includes a UI test target folder (`{ProjectName}UITests/`) using XCUITest.

Target platform defaults: **iOS 26**, **Swift 6.2**, **Swift 6 concurrency**, **SwiftUI**, **MVVM with `@Observable`**.

## Templates & helpers

All starter file templates live in `assets/`, named `*.template`. Placeholder tokens use `{{Key}}` (double braces). Substitute them with `scripts/substitute.sh`:

```bash
scripts/substitute.sh <template> <dest> KEY=VALUE [KEY=VALUE ...]
```

The script refuses to overwrite an existing destination unless `FORCE=1`, and warns if any `{{...}}` placeholders remain unfilled. **Read each template only at the moment you are about to write its destination — do not preload them all up front.**

`references/xcodegen-cheatsheet.md` is loaded on demand if the generated `project.yml` fails to parse or you need a field the template doesn't cover.

### Asset → destination map

Each template's first line is a `# placeholders: ...` comment listing the keys it needs. Strip that comment from the rendered output.

- `project.yml.template` → `./project.yml`
- `gitignore.template` → `./.gitignore`
- `swiftlint.yml.template` → `./.swiftlint.yml` (skip if SwiftLint disabled)
- `Environment.xcconfig.template` → `{ProjectName}/Config/Environment.xcconfig` (committed, references `${API_HOST_NAME}` from env + optionally includes the local file)
- `Environment-Local.xcconfig.template` → `{ProjectName}/Config/Environment-Local.xcconfig` (gitignored, has empty values for the user to fill)
- `App.swift.template` → `{ProjectName}/{ProjectName}App.swift`
- `ContentView.swift.template` → `{ProjectName}/ContentView.swift`
- `AppConfig.swift.template` → `{ProjectName}/Config/AppConfig.swift` (Codable struct mirroring the keys listed under the app target's `info.properties` in `project.yml`; `project.yml` excludes `Config/*.xcconfig` and the generated `Config/Info.plist` from compile sources)
- `Decodable+fromInfoPlist.swift.template` → `{ProjectName}/Extensions/Decodable+fromInfoPlist.swift` (generic decoder used by `AppConfig.fromInfoPList()`)
- `DependencyContainer.swift.template` → `{ProjectName}/DI/DependencyContainer.swift` (injects `AppConfig.fromInfoPList()`)
- `Tests.swift.template` → `{ProjectName}Tests/{ProjectName}Tests.swift`
- `UITests.swift.template` → `{ProjectName}UITests/{ProjectName}UITests.swift`
- *(no CI templates)* — GitHub Actions CI comes from the separate **xcode-ci** skill (see post-build prompt B).
- `CLAUDE.md.template` → `./CLAUDE.md` (only if AI files = yes)
- `AGENTS_SHARED.md.template` → `./AGENTS_SHARED.md` (only if AI files = yes)
- *(no `agents.md` template)* — created as a symlink: `ln -sf AGENTS_SHARED.md agents.md` (only if AI files = yes **and** symlink question = yes)
- `persistence/SwiftDataItem.swift.template` → `{ProjectName}/Models/Item.swift` (if SwiftData)
- `persistence/SwiftDataAppHook.swift.template` → merge snippet into `{ProjectName}App.swift`
- `persistence/CoreDataStack.swift.template` → `{ProjectName}/Services/CoreDataStack.swift` (if CoreData; also read `persistence/CoreData.README.md`)
- `persistence/GRDBDatabase.swift.template` → `{ProjectName}/Services/AppDatabase.swift` (if GRDB)

For `project.yml`, the `SwiftLintBuildPhase` placeholder takes either an empty string (disabled) or a `preBuildScripts:` YAML block running SwiftLint — open the template to see exactly where it slots in. Emit exactly this block (indented to sit under the app target, i.e. 4 spaces):

```yaml
    preBuildScripts:
      - name: SwiftLint
        basedOnDependencyAnalysis: false
        script: |
          if [[ "$(uname -m)" == arm64 ]]; then export PATH="/opt/homebrew/bin:$PATH"; fi
          if which swiftlint >/dev/null; then
            swiftlint
          else
            echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
          fi
```

The `uname -m` PATH prepend is SwiftLint's recommended guard and is **required**: when Xcode is launched from the Dock, launchd's PATH lacks `/opt/homebrew/bin`, so a bare `if which swiftlint` guard silently no-ops on Apple Silicon.

## User config

Nothing user-specific is hard-coded. Read `~/.config/bootstrap-xcode-project.json` before asking any question:

```json
{ "bundleIdPrefix": "com.example", "githubOrg": "<organization login>" }
```

- **`bundleIdPrefix`** — reverse-DNS prefix for new apps (`com.example` → bundle ID `com.example.{ProjectName}`). If the key is missing, ask once: *"Which bundle ID prefix should new apps use (reverse DNS, such as `com.yourname`)?"* It must match `^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$`; ask again if it doesn't.
- **`githubOrg`** — the GitHub organization for new repos and the shared self-hosted runner. If the key is missing, ask once: *"Which GitHub organization should new repos and the shared self-hosted runner live in? Leave blank to use your personal account."*
  - Blank or `null` means personal account: the defaults then become `GitHub owner: personal account` and `CI runner: GitHub-hosted`, because personal-account self-hosted runners are repo-scoped (see the xcode-ci skill).
  - Verify the org and the user's membership: `gh api user/memberships/orgs/{githubOrg} -q .state` must print `active`. If it doesn't, surface the error and ask again.
- Ask only for missing keys, and save each answer by merging it into the file so the other keys stay (for example `jq --arg v "<answer>" '. + {bundleIdPrefix: $v}'`, written back through a temp file; create `~/.config/` and the file if needed).
- `{bundleIdPrefix}` and `{githubOrg}` below mean these values.

## Inputs to collect (ask in this order)

Always recommend an answer. If the user says "default" / "你決定", apply the recommended value and move on.

1. **Project name** — required. PascalCase, valid Swift identifier, no spaces. If passed as a slash-command argument, remind it should be PascalCase but accept what's given.

2. **Use all recommended defaults?** — default **yes**. Show the full recommended config block (below) and ask whether to apply it as-is. If yes, **skip questions 3–8** and go straight to the generation summary. If no, fall through and ask each remaining question one at a time.

   Recommended defaults block to display verbatim:
   ```
   Bundle ID:      {bundleIdPrefix}.{ProjectName}
   Persistence:    SwiftData
   SwiftLint:      yes
   MVVM scaffold:  yes (Views/ ViewModels/ Services/ Repositories/ Models/ DI/ Extensions/ Config/)
   AI files:       CLAUDE.md + AGENTS_SHARED.md + agents.md symlink
   Gitignore AI:   no (commit CLAUDE.md and agents.md so teammates/agents see them)
   GitHub owner:   {githubOrg} (organization, from the user config) — if you push
   CI runner:      self-hosted org runner (macOS, ARM64) — if you add CI
   ```

   GitHub push is **not** decided by this block — it's asked as a post-build prompt (see below) so the user can decide based on whether the build actually succeeded. The last two lines only pre-fill the defaults of those prompts.

3. **Bundle identifier** — default `{bundleIdPrefix}.{ProjectName}`.
4. **Persistence storage** — *"Do you need persistence? SwiftData / CoreData / GRDB / none?"*
   - Recommend **SwiftData** for new iOS 26 projects.
   - Suggest **GRDB** if the user needs heavy relational querying or fine SQL control.
   - Suggest **CoreData** only if migrating from an existing CoreData store.
   - One-line justification with the recommendation.
5. **SwiftLint** — default **yes**. Project CLAUDE.md requires SwiftLint before build.
6. **Folder scaffold (MVVM)** — default **yes**. Create empty group folders `Views/`, `ViewModels/`, `Services/`, `Repositories/`, `Models/`, `DI/`, `Extensions/`, `Config/`.
7. **Include AI instruction files** — *"Generate `CLAUDE.md` and `AGENTS_SHARED.md` in the project?"* Default **yes**. These propagate the project's Swift / MVVM / Git conventions to any agent (Claude, Codex, Cursor) that opens the repo later. Skip only if the user wants a completely vanilla project with no AI guidance.
8. **Create `agents.md` symlink** — *only ask if step 7 = yes.* *"Create `agents.md` symlinked to `AGENTS_SHARED.md` (for non-Claude agents that look for lowercase `agents.md`)?"* Default **yes**. The symlink keeps a single source of truth.
9. **`.gitignore` policy for AI files** — *only ask if step 7 = yes.* *"Add `CLAUDE.md` (and `agents.md` symlink if present) to `.gitignore`?"* Surface tradeoff: ignore = private; commit = shared with teammates / other agents. `AGENTS_SHARED.md` always stays committed when present (it's the shared rules other AI files `@`-include).

## Post-build prompts (asked after build verification passes)

Ask these **regardless of whether the user chose "use all defaults"** — the user needs to see a successful build before committing to a remote push.

A. **Push to GitHub?** — no default. *"Build succeeded. Push to a new private GitHub repo?"* If no, stop here. If yes, continue.
B. **GitHub Actions CI?** — only if A = yes. Default **yes**. *"Add GitHub Actions CI: a fast PR gate (SwiftLint + unit tests) and a separate UI test workflow?"* CI is set up by the **xcode-ci** skill, which also asks where CI runs (self-hosted org runner by default, GitHub-hosted on request). If the xcode-ci skill is not available in this session, say so, tell the user to install it (`/plugin install xcode-ci@<marketplace>`, from the same marketplace as this skill), and continue without CI.

Runner facts (checking, registering, sleep, disk) live in the xcode-ci skill's `references/self-hosted-runner.md`.

## Generation steps

Run these only after all questions are answered. Echo a one-line config summary and get final confirmation before writing files.

1. **Verify tooling:** `xcodegen --version`, `xcodebuild -version`. If `xcodegen` is missing, instruct `brew install xcodegen` and stop. (`gh` is checked later, only if the user opts into pushing.)
2. **Create directory** `{ProjectName}/` and `cd` into it. Refuse if it already exists.
3. **Render `project.yml`** from `assets/project.yml.template` via `scripts/substitute.sh`, passing all five placeholders (`BundleIDPrefix={bundleIdPrefix}`, `BundleID` = the bundle identifier from input 3). For `SwiftLintBuildPhase`, pass the YAML block above (quoted properly in shell) when SwiftLint is enabled, otherwise pass an empty string.
4. **Create source folders:** `{ProjectName}/{Views,ViewModels,Services,Repositories,Models,DI,Extensions,Config}`, `{ProjectName}Tests/`, `{ProjectName}UITests/`. Then `touch` a `.gitkeep` in every folder that will still be empty after step 6 renders sources (typically `Views/`, `ViewModels/`, `Services/`, `Repositories/`, and `Models/` when no persistence file lands there). Do this **before** `xcodegen generate` (step 10), never after: XcodeGen records each `.gitkeep` as a file reference in the pbxproj (in its group, with no build phase — it is not compiled or bundled), so adding them after generating means the next `xcodegen generate` rewrites the pbxproj (drift). Adding them first keeps regeneration stable, and git tracks the otherwise-empty folders so a fresh clone regenerates an identical project. Do **not** exclude `**/.gitkeep` in `project.yml` — a folder whose only file is excluded is dropped from the project entirely, which deletes the empty MVVM groups. `Config/` lives **inside** `{ProjectName}/` — `project.yml` adds the whole app folder as sources but excludes `Config/*.xcconfig` from compilation, and points `configFiles` at the xcconfig path under `{ProjectName}/Config/`.
5. **Render xcconfig pair into `{ProjectName}/Config/`:** copy `Environment.xcconfig.template` → `{ProjectName}/Config/Environment.xcconfig` and `Environment-Local.xcconfig.template` → `{ProjectName}/Config/Environment-Local.xcconfig` (no substitution). The committed `Environment.xcconfig` references `${API_HOST_NAME}` and `#include?`s the local file; `Environment-Local.xcconfig` is gitignored. Runtime exposure goes through the app target's `info:` block in `project.yml` — XcodeGen generates `{ProjectName}/Config/Info.plist` with `<NAME> = $(<NAME>)` entries that Xcode resolves from build settings. To add more credentials later: (a) add the key to both xcconfig files, (b) add `<NAME>: "$(<NAME>)"` under the app target's `info.properties` in `project.yml` and re-run `xcodegen generate`, (c) add the field to `AppConfig` so it gets decoded. **Never expose custom keys via `INFOPLIST_KEY_<NAME>` build settings** — `GENERATE_INFOPLIST_FILE` only injects Apple's curated set of `INFOPLIST_KEY_*` names and silently drops custom ones, so decoding `AppConfig` crashes at launch with `keyNotFound`.
6. **Render starter sources** from each template in the asset index above, in this order:
   - `Decodable+fromInfoPlist.swift` → `{ProjectName}/Extensions/` (copy verbatim — no substitution)
   - `AppConfig.swift` → `{ProjectName}/Config/` (copy verbatim — `Codable` struct whose property names must exactly match the keys under `info.properties` in `project.yml`)
   - `DependencyContainer.swift` → `{ProjectName}/DI/` (copy verbatim — wires `AppConfig.fromInfoPList()` into the container)
   - `{ProjectName}App.swift`
   - `ContentView.swift`
   - `{ProjectName}Tests.swift`
   - `{ProjectName}UITests.swift`
   - If persistence chosen, render the matching persistence template(s). For SwiftData, also merge the `modelContainer(for:)` modifier into `{ProjectName}App.swift` per `SwiftDataAppHook.swift.template`. For CoreData, surface the contents of `CoreData.README.md` to the user — `.xcdatamodeld` must be created manually in Xcode. For GRDB, remind the user to add the GRDB package in `project.yml` and re-run xcodegen.
7. **Render `.swiftlint.yml`** (skip if SwiftLint disabled).
8. **Render AI instruction files** if inputs step 7 = yes: `CLAUDE.md` and `AGENTS_SHARED.md` to project root. If inputs step 8 = yes, also run `ln -sf AGENTS_SHARED.md agents.md` from the project root (must run after `AGENTS_SHARED.md` exists).
9. **Render `.gitignore`.** `*-Local.xcconfig` is always ignored (built into the template). If AI files were opted in **and** the user chose to gitignore them, pass `AIFilesIgnore=$'CLAUDE.md\nagents.md\n'` (lowercase `agents.md` to match the symlink); otherwise pass empty string. Never gitignore `AGENTS_SHARED.md`.
10. **Generate Xcode project:** `xcodegen generate`. If it fails, load `references/xcodegen-cheatsheet.md` and debug.
11. **Build verification:** `xcodebuild -scheme {ProjectName} -destination 'platform=iOS Simulator,name=<sim>' build`, where `<sim>` is picked dynamically — do **not** hardcode a device name; older-generation simulators may lack a runtime new enough for the deployment target (and `simctl list devices available` still lists those, so don't trust it either). Pick an iPhone from the scheme's actual eligible destinations: `xcodebuild -showdestinations -scheme {ProjectName} 2>/dev/null | grep 'platform:iOS Simulator' | sed -n 's/.*name:\(iPhone[^}]*\).*/\1/p' | sed 's/ *$//' | tail -1`. If the build fails, report and stop — do not proceed to the post-build prompts.
12. **Post-build prompt A — push to GitHub?** Ask the user (always, even in "use all defaults" mode). If no, jump to Output. If yes:
    - Verify `gh --version` + `gh auth status`. If not authenticated, surface the error and stop.
    - Ask post-build prompt B (GitHub Actions CI?). If yes, run `git init -b main` and then invoke the **xcode-ci** skill, so the workflows land in the initial commit (actionlint needs the git root to resolve the local `prepare-ios` action). Pass what is already known so it only asks for the runner: new repo not created yet, owner `{githubOrg}` (or the personal account), `Scheme={ProjectName}`, `UnitTestTarget={ProjectName}Tests`, `UITestTarget={ProjectName}UITests`, `CIMajor` = the major of `IOSDeployment` (`26.0` → `26`), XcodeGen project, no existing CI. It renders and validates the files; leave committing and pushing to the steps below.
    - `git init -b main` (skip if already done for CI) `&& git add . && git commit -m "feat: bootstrap {ProjectName}"` (follows the project's `feat/fix/refactor:` convention).
    - Org: `gh repo create {githubOrg}/{ProjectName} --private --source=. --remote=origin --push`. Personal account: `gh repo create {ProjectName} --private --source=. --remote=origin --push`.
    - If CI was added, create the label that opts a PR into UI tests (xcode-ci could not, because the repo did not exist yet): `gh label create ui-tests --repo <owner>/{ProjectName} --color 1D76DB --description "Run the UI test workflow on this PR" --force`.
    - If CI was added, watch the first runs once (`gh run list --repo <owner>/{ProjectName} --limit 2`), and report whether `CI` and `UI Tests` were picked up by the expected runner.

## Output

End with a short summary:
- Path to the generated `.xcodeproj`.
- GitHub repo URL (if created).
- CI: which runner it targets, that UI tests run on main / on demand / with the `ui-tests` PR label, and whether the first runs were picked up (or are queued because the runner is offline).
- Next steps: `open {ProjectName}.xcodeproj` or `xcodebuild test -scheme {ProjectName} -destination 'platform=iOS Simulator,name=<sim>'` (reuse the simulator picked in step 11 — plain `xcodebuild test` with no destination fails against the generic iOS device).

## Rules

- Generated code, comments, and file content must be in **English** (per project CLAUDE.md).
- 4-space indentation in all Swift files.
- Do not use `@unchecked Sendable`.
- Prefer `async/await`; no completion-handler APIs in starter code.
- Never push to a public repo. If the user asks for public, confirm twice.
- Never make a repo public to get free hosted CI minutes; use the self-hosted org runner instead.
- Never overwrite an existing `{ProjectName}/` directory — stop and ask.
- After each `substitute.sh` call, scan the destination for stray `{{...}}` (the script already warns; treat any warning as a fatal error and fix the call).
