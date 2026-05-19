---
name: bootstrap-xcode-project
description: Scaffold a new iOS Xcode project via XcodeGen — .xcodeproj, Swift Testing + XCUITest targets, MVVM folders, optional SwiftData/CoreData/GRDB, SwiftLint, private GitHub repo, GitHub Actions CI. Triggers on "bootstrap xcode", "new iOS project", "建一個新的 Xcode project", or any request to start a fresh iOS app from scratch.
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
- `AppConfig.swift.template` → `{ProjectName}/Config/AppConfig.swift` (Codable struct mirroring the xcconfig keys exposed via `INFOPLIST_KEY_*`; `project.yml` excludes `Config/*.xcconfig` from compile sources)
- `Decodable+fromInfoPlist.swift.template` → `{ProjectName}/Extensions/Decodable+fromInfoPlist.swift` (generic decoder used by `AppConfig.fromInfoPList()`)
- `DependencyContainer.swift.template` → `{ProjectName}/DI/DependencyContainer.swift` (injects `AppConfig.fromInfoPList()`)
- `Tests.swift.template` → `{ProjectName}Tests/{ProjectName}Tests.swift`
- `UITests.swift.template` → `{ProjectName}UITests/{ProjectName}UITests.swift`
- `ci.yml.template` → `.github/workflows/ci.yml` (only if GitHub + CI)
- `CLAUDE.md.template` → `./CLAUDE.md` (only if AI files = yes)
- `AGENTS_SHARED.md.template` → `./AGENTS_SHARED.md` (only if AI files = yes)
- *(no `agents.md` template)* — created as a symlink: `ln -sf AGENTS_SHARED.md agents.md` (only if AI files = yes **and** symlink question = yes)
- `persistence/SwiftDataItem.swift.template` → `{ProjectName}/Models/Item.swift` (if SwiftData)
- `persistence/SwiftDataAppHook.swift.template` → merge snippet into `{ProjectName}App.swift`
- `persistence/CoreDataStack.swift.template` → `{ProjectName}/Services/CoreDataStack.swift` (if CoreData; also read `persistence/CoreData.README.md`)
- `persistence/GRDBDatabase.swift.template` → `{ProjectName}/Services/AppDatabase.swift` (if GRDB)

For `project.yml`, the `SwiftLintBuildPhase` placeholder takes either an empty string (disabled) or a `preBuildScripts:` YAML block running SwiftLint — open the template to see exactly where it slots in, and emit a standard `if which swiftlint` shell guard.

## Inputs to collect (ask in this order)

Always recommend an answer. If the user says "default" / "你決定", apply the recommended value and move on.

1. **Project name** — required. PascalCase, valid Swift identifier, no spaces. If passed as a slash-command argument, remind it should be PascalCase but accept what's given.

2. **Use all recommended defaults?** — default **yes**. Show the full recommended config block (below) and ask whether to apply it as-is. If yes, **skip questions 3–8** and go straight to the generation summary. If no, fall through and ask each remaining question one at a time.

   Recommended defaults block to display verbatim:
   ```
   Bundle ID:      com.cwlab.{ProjectName}
   Persistence:    SwiftData
   SwiftLint:      yes
   MVVM scaffold:  yes (Views/ ViewModels/ Services/ Repositories/ Models/ DI/ Extensions/ Config/)
   AI files:       CLAUDE.md + AGENTS_SHARED.md + agents.md symlink
   Gitignore AI:   no (commit CLAUDE.md and agents.md so teammates/agents see them)
   ```

   GitHub push is **not** part of this block — it's asked as a post-build prompt (see below) so the user can decide based on whether the build actually succeeded.

3. **Bundle identifier** — default `com.cwlab.{ProjectName}`.
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
B. **GitHub Actions CI?** — only if A = yes. Default **yes**. *"Include `.github/workflows/ci.yml` that runs `xcodebuild test` on every PR?"*

## Generation steps

Run these only after all questions are answered. Echo a one-line config summary and get final confirmation before writing files.

1. **Verify tooling:** `xcodegen --version`, `xcodebuild -version`. If `xcodegen` is missing, instruct `brew install xcodegen` and stop. (`gh` is checked later, only if the user opts into pushing.)
2. **Create directory** `{ProjectName}/` and `cd` into it. Refuse if it already exists.
3. **Render `project.yml`** from `assets/project.yml.template` via `scripts/substitute.sh`, passing all five placeholders. For `SwiftLintBuildPhase`, pass the YAML block above (quoted properly in shell) when SwiftLint is enabled, otherwise pass an empty string.
4. **Create source folders:** `{ProjectName}/{Views,ViewModels,Services,Repositories,Models,DI,Extensions,Config}`, `{ProjectName}Tests/`, `{ProjectName}UITests/`. `Config/` lives **inside** `{ProjectName}/` — `project.yml` adds the whole app folder as sources but excludes `Config/*.xcconfig` from compilation, and points `configFiles` at the xcconfig path under `{ProjectName}/Config/`.
5. **Render xcconfig pair into `{ProjectName}/Config/`:** copy `Environment.xcconfig.template` → `{ProjectName}/Config/Environment.xcconfig` and `Environment-Local.xcconfig.template` → `{ProjectName}/Config/Environment-Local.xcconfig` (no substitution). The committed `Environment.xcconfig` references `${API_HOST_NAME}` and `#include?`s the local file; `Environment-Local.xcconfig` is gitignored. To add more credentials later: (a) add the key to both xcconfig files, (b) add a matching `INFOPLIST_KEY_<NAME>` line in `Environment.xcconfig`, (c) add the field to `AppConfig` so it gets decoded.
6. **Render starter sources** from each template in the asset index above, in this order:
   - `Decodable+fromInfoPlist.swift` → `{ProjectName}/Extensions/` (copy verbatim — no substitution)
   - `AppConfig.swift` → `{ProjectName}/Config/` (copy verbatim — `Codable` struct whose property names must exactly match the `INFOPLIST_KEY_*` suffixes in `Environment.xcconfig`)
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
11. **Build verification:** `xcodebuild -scheme {ProjectName} -destination 'platform=iOS Simulator,name=iPhone 16' build`. If it fails, report and stop — do not proceed to the post-build prompts.
12. **Post-build prompt A — push to GitHub?** Ask the user (always, even in "use all defaults" mode). If no, jump to Output. If yes:
    - Verify `gh --version` + `gh auth status`. If not authenticated, surface the error and stop.
    - Ask post-build prompt B (GitHub Actions CI?). If yes, render `.github/workflows/ci.yml` from `ci.yml.template` now (so it lands in the initial commit).
    - `git init && git add . && git commit -m "feat: bootstrap {ProjectName}"` (follows the project's `feat/fix/refactor:` convention).
    - `gh repo create {ProjectName} --private --source=. --remote=origin --push`.

## Output

End with a short summary:
- Path to the generated `.xcodeproj`.
- GitHub repo URL (if created).
- Next steps: `open {ProjectName}.xcodeproj` or `xcodebuild test -scheme {ProjectName}`.

## Rules

- Generated code, comments, and file content must be in **English** (per project CLAUDE.md).
- 4-space indentation in all Swift files.
- Do not use `@unchecked Sendable`.
- Prefer `async/await`; no completion-handler APIs in starter code.
- Never push to a public repo. If the user asks for public, confirm twice.
- Never overwrite an existing `{ProjectName}/` directory — stop and ask.
- After each `substitute.sh` call, scan the destination for stray `{{...}}` (the script already warns; treat any warning as a fatal error and fix the call).
