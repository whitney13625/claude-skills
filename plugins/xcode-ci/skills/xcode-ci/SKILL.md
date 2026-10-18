---
name: xcode-ci
description: Set up or upgrade GitHub Actions CI for an Xcode app project — a fast PR gate (SwiftLint + unit tests) and a separate UI test workflow that runs on main, on demand, and on PRs labelled `ui-tests`; on a self-hosted macOS runner with persistent DerivedData, or on GitHub-hosted runners. iOS apps today. Triggers on "set up CI", "add GitHub Actions", "CI is too slow", "split UI tests out of CI", "self-hosted runner", "幫這個專案設 CI", or when bootstrap-xcode-project asks for CI.
---

# Xcode CI

Add a two-workflow GitHub Actions setup to an Xcode app repo, new or existing.

The XCUITest suite is the slow part of iOS CI, so it is kept out of the PR gate:

- **`ci.yml`** (every PR and push to `main`): SwiftLint (when `.swiftlint.yml` exists) and `xcodebuild test -only-testing:<UnitTestTarget>`.
- **`ui-tests.yml`**: `xcodebuild test -only-testing:<UITestTarget>`. Runs on push to `main`, on `workflow_dispatch`, and on a PR while it carries the **`ui-tests`** label (`pull_request` types include `labeled`; the job's `if:` checks the label). The self-hosted variant also runs weekly (`schedule`) from a clean DerivedData; the hosted variant skips the schedule because every hosted run already starts clean.
- **Self-hosted only:** both workflows call the composite action `.github/actions/prepare-ios`, which adds Homebrew to PATH, installs XcodeGen/jq/SwiftLint, selects the newest installed Xcode of major `CI_MAJOR`, runs `xcodegen generate` when `project.yml` exists, creates a throwaway simulator, and keeps DerivedData at `~/ci-cache/$RUNNER_NAME/$GITHUB_REPOSITORY/xcode-<version>/DerivedData` so builds stay incremental between runs. The GitHub-hosted variant keeps DerivedData in `$RUNNER_TEMP`.

**Platforms:** the templates build and test an iOS app on an iPhone simulator. watchOS, macOS and visionOS targets are not covered yet; for those, say so and stop rather than rendering iOS workflows.

## Templates & helpers

Templates live in `assets/`, named `*.template`, with `{{Key}}` placeholders. Render with:

```bash
scripts/substitute.sh <template> <dest> KEY=VALUE [KEY=VALUE ...]
```

It refuses to overwrite an existing destination unless `FORCE=1`, and warns about unfilled `{{Key}}` placeholders (treat a warning as a fatal error). `${{ ... }}` GitHub expressions are not placeholders. Each template's first line is a `# placeholders: ...` comment; delete it from the rendered file.

| Runner | Template | Destination | Placeholders |
|---|---|---|---|
| Self-hosted | `ci-selfhosted.yml.template` | `.github/workflows/ci.yml` | `Scheme`, `UnitTestTarget`, `GitHubOwner`, `CIMajor` |
| Self-hosted | `ui-tests-selfhosted.yml.template` | `.github/workflows/ui-tests.yml` | `Scheme`, `UITestTarget`, `CIMajor` |
| Self-hosted | `prepare-ios-action.yml.template` | `.github/actions/prepare-ios/action.yml` | none |
| GitHub-hosted | `ci.yml.template` | `.github/workflows/ci.yml` | `Scheme`, `UnitTestTarget` |
| GitHub-hosted | `ui-tests.yml.template` | `.github/workflows/ui-tests.yml` | `Scheme`, `UITestTarget` |

`references/self-hosted-runner.md` holds the runner facts (org vs personal account, checking, registering, sleep, disk). Load it when the user picks the self-hosted runner and it is offline or missing, or when they ask about the runner.

## Inputs

When another skill (such as bootstrap-xcode-project) invokes this one, it passes the values it already knows; use them and ask only for the rest. Otherwise detect each value, show what you found, and confirm. Always recommend an answer.

1. **Repo root and owner.** Work from the git root. Owner = the `origin` remote's owner (`gh repo view --json owner -q .owner.login`), or the value the caller passed for a repo that is not created yet. Note whether the owner is an organization (`gh api users/<owner> -q .type` prints `Organization`).
2. **Scheme.** XcodeGen projects: the `name:` in `project.yml` (its app scheme). Otherwise `xcodebuild -list -json` and pick the app's shared scheme. The scheme must be shared (`xcshareddata/xcschemes/`) or CI cannot see it; if it is not, tell the user to tick "Shared" in Xcode's scheme manager and commit it.
3. **Test targets.** From the scheme's test action: the unit test target (`UnitTestTarget`, usually `<App>Tests`) and the UI test target (`UITestTarget`, usually `<App>UITests`). Do not assume the names. No UI test target → render only `ci.yml` (and the action), skip `ui-tests.yml` and the label.
4. **`CIMajor`.** The major of the app's iOS deployment target (`IPHONEOS_DEPLOYMENT_TARGET`, or `deploymentTarget` in `project.yml`; `26.0` → `26`). It pins the Xcode and simulator runtime major on the self-hosted runner; raising it later is a deliberate change.
5. **Runner.** Always ask. Default **self-hosted** when the owner is an organization, **GitHub-hosted** otherwise (personal-account self-hosted runners are repo-scoped; see the reference).
   - Self-hosted: check the org runner (`gh api orgs/<owner>/actions/runners`, needs `admin:org`). If none with the `macOS` label is `online`, say CI will queue until it is and load `references/self-hosted-runner.md`. Do not silently fall back to GitHub-hosted.
   - GitHub-hosted `macos-26`: uses Actions minutes, which can run out or be blocked on a private repo. Never make a repo public to get free minutes.

## Steps

1. **Existing CI.** List `.github/workflows/` and `.github/actions/`. For each destination that already exists, do not overwrite it blindly:
   - Diff it against the rendered template and list the steps that are project-specific (extra packages tested, scripts, linters, other jobs). Carry them into the new file: steps that must gate PRs go into `ci.yml` after the unit test step, extra jobs stay as jobs in `ci.yml`. Show the merged result and get a yes before writing it (`FORCE=1`).
   - Another workflow that also runs `xcodebuild test` (for example `build.yml`): ask whether the new `ci.yml` replaces it; two gates double the CI time.
2. **Required checks.** If `main` is protected, read `gh api repos/<owner>/<repo>/branches/main/protection/required_status_checks -q '.contexts'`. The new PR job is named `Lint & Unit Test`; a required check under the old job name (for example `Build & Test`) will block every PR forever. Tell the user which context to replace, and do not change branch protection yourself unless they ask. Do not make `UI Test` a required check: it is skipped on unlabelled PRs.
3. **Render** the files for the chosen runner from the table above, then delete each file's `# placeholders:` line. If the `.xcodeproj` or `.xcworkspace` is not at the repo root, or the root holds both a workspace and a project, add `-workspace`/`-project` to every `xcodebuild` call (and `working-directory:` where needed) by hand.
4. **Validate** with `actionlint` from the repo root (it must be inside a git repo to resolve `./.github/actions/prepare-ios` and check its inputs). If `actionlint` is missing, suggest `brew install actionlint` and at least parse each file: `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }' .github/workflows/*.yml .github/actions/*/action.yml`.
5. **Label.** If the repo exists on GitHub and `ui-tests.yml` was rendered: `gh label create ui-tests --repo <owner>/<repo> --color 1D76DB --description "Run the UI test workflow on this PR" --force`. If the repo is not created yet, tell the caller to run this right after creating it.
6. **Commit.** Follow the repo's own rules (branch naming, PR flow, whether to ask first). Never push or open a PR without the user's go-ahead. For an existing repo, a branch like `ci/split-ui-tests` and a PR is the usual shape.
7. **First runs.** Once pushed, check `gh run list --repo <owner>/<repo> --limit 3` once and report whether `CI` was picked up by the expected runner. On a PR, `UI Tests` shows as skipped until the `ui-tests` label is added.

## Output

- Files written, the runner they target, and any project-specific steps carried over.
- The required-check change the user needs to make, if any.
- How to run UI tests: merge to `main`, add the `ui-tests` label to a PR, or `gh workflow run ui-tests.yml`.
- On self-hosted: that the first run builds from scratch and later runs reuse DerivedData.
