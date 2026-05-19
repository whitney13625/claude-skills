---
name: publish-skill
description: Promote a local Claude Code skill (from `~/.claude/skills/`, the current project's `.claude/skills/`, or an explicit path) into a Claude Code marketplace repo as a plugin, generating `plugin.json`, updating `marketplace.json` + README, then committing and pushing to GitHub. Also handles updates to already-published skills. Use when the user says "publish skill X", "push my skill to marketplace", "promote local skill", or invokes `/publish-skill <name>`.
---

# Publish skill to marketplace repo

Promotes a skill folder into a Claude Code marketplace repo (`<repo>/plugins/<name>/skills/<name>/`), wires up the manifests, updates the README, commits, and pushes.

**Nothing user-specific is baked into this skill.** Owner name, marketplace name, GitHub user — all resolved at runtime from the target repo's `marketplace.json` and the user's `gh` / `git` config. The same skill works for any user with any marketplace repo.

`SOURCE_DIR` (used throughout) is the absolute path of the local skill folder to publish, resolved in step 1.

## Inputs to collect (ask one at a time)

1. **Source skill** — required. Discover candidates and let the user pick. Resolve to an absolute `SOURCE_DIR`.

   **Discovery order** (run all three, then merge results):
   - **global**: scan `~/.claude/skills/*/SKILL.md`.
   - **project**: scan `$(pwd)/.claude/skills/*/SKILL.md` (skills local to the current directory's repo).
   - **explicit**: any path the user gives as an argument.

   **Behavior:**
   - If the user passed `<name>` as a slash-command argument:
     - One match across global + project → use it directly; print `using <kind>: <path>`.
     - Match in both → ask which one (show full paths, mark `[global]` / `[project]`).
     - No matches → ask the user to type an explicit path (must be a folder containing `SKILL.md`).
   - If no argument:
     - List all discovered candidates as a single picker, e.g.:
       ```
       1. publish-skill          [global]
       2. bootstrap-xcode-project [global]
       3. project-only-helper    [project]
       4. <type a path>
       ```
   - Validate the chosen path: must be a folder, must contain `SKILL.md`, frontmatter must have valid `name:` field. The folder *basename* becomes `<name>` (overrides the frontmatter `name` if they differ, and warns the user).

   Store the result as `SOURCE_DIR` and the `<kind>` (`global` / `project` / `explicit`) — the kind affects the post-publish symlink question.

2. **Marketplace repo path** — absolute path, must be a git repo with `.claude-plugin/marketplace.json`. Resolution order:
   1. `$CLAUDE_MARKETPLACE_REPO` env var, if set.
   2. `defaultRepo` field of `~/.config/claude-publish-skill.json`, if present — confirm with the user before using.
   3. Otherwise ask. Save the answer to `~/.config/claude-publish-skill.json` (create if missing) under `defaultRepo` for next time.

3. **Plugin description** — required. Default = the `description:` frontmatter field of `$SOURCE_DIR/SKILL.md` (extract via `sed -n '/^description:/,/^[a-z]\+:/p' "$SOURCE_DIR/SKILL.md" | head -1`); let the user edit before applying.

4. **Plugin category** — default `development`. Common alternatives: `productivity`, `design`, `data`, `documentation`. Skip the question if the user already chose `development` in defaults mode.

## Detect mode

Run `[ -d "<repo>/plugins/<name>" ]`:
- Does **not** exist → **add mode** (full new-skill flow).
- Exists → **update mode** (sync local → repo only).

Show the detected mode to the user before proceeding.

## Resolve marketplace metadata

From `<repo>/.claude-plugin/marketplace.json`:

```bash
MARKETPLACE_NAME=$(jq -r .name      <repo>/.claude-plugin/marketplace.json)
OWNER_NAME=$(     jq -r .owner.name <repo>/.claude-plugin/marketplace.json)
```

If either is empty / null:
- `OWNER_NAME` fallback: `git -C <repo> config user.name`.
- `MARKETPLACE_NAME` missing is a fatal error — the marketplace isn't set up; tell the user to fix it manually.

Also resolve `GH_USER=$(gh api user -q .login)` for the install-command hint at the end.

## Pre-flight checks

Before mutating anything:

1. `<repo>` exists, is a git directory.
2. `<repo>/.claude-plugin/marketplace.json` parses as JSON (`jq . > /dev/null`).
3. `<name>` matches `^[a-z][a-z0-9-]+$` (lowercase + dashes; standard plugin naming).
4. Working tree is clean OR the only changes are inside `plugins/<name>/` (we're about to overwrite those). If anything else is dirty, surface a warning and require explicit confirmation to proceed.
5. **Add mode only:** no entry with `.name == "<name>"` already in `marketplace.json` `.plugins`. Refuse if it is — the user is in update mode but the folder is missing, which means something is corrupted.

## PII / sensitive-content scan

Run before any file mutation. Scan `$SOURCE_DIR` (recursively, all files) for patterns that commonly leak into otherwise-generic skills:

```bash
grep -rIn -E '/Users/[a-z0-9._-]+|/home/[a-z0-9._-]+' "$SOURCE_DIR"            # personal home paths
grep -rIn -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$SOURCE_DIR"    # email addresses
grep -rIn -iE '(secret|token|api[_-]?key|password|bearer|access[_-]?key)\s*[:=]' "$SOURCE_DIR"  # credentials
grep -rIn -E 'git@github\.com:[A-Za-z0-9_-]+/|github\.com/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+' "$SOURCE_DIR"  # hardcoded git remotes
```

If anything matches:
1. Show the user the matches (file:line + matched text) grouped by category.
2. Ask: *"Proceed anyway?"* — default **no**. The matches might be legitimate (example values in templates, or placeholder URLs in docs), but the user must explicitly acknowledge each category.
3. If the user says proceed, log the matches in the final summary so they can review post-publish.

**This check fires for all source kinds** but is especially important for `project` sources (often contain repo-specific paths) and `explicit` sources (provenance unknown).

The patterns are heuristics, not a guarantee. Add new patterns over time as new leak shapes surface.

## Add mode — execution

1. `mkdir -p <repo>/plugins/<name>/.claude-plugin`
2. `cp -R "$SOURCE_DIR" <repo>/plugins/<name>/skills/<name>` (note: trailing `<name>` — copy *as* the target dir name even if SOURCE_DIR basename differs)
3. Write `<repo>/plugins/<name>/.claude-plugin/plugin.json`:
   ```json
   {
     "name": "<name>",
     "description": "<plugin description from input 3>",
     "version": "0.1.0",
     "author": { "name": "<OWNER_NAME>" }
   }
   ```
4. **Insert into `marketplace.json`** — append to the `plugins` array:
   ```bash
   tmp=$(mktemp) && jq \
     --arg name "<name>" --arg desc "<desc>" --arg cat "<category>" \
     '.plugins += [{name: $name, description: $desc, category: $cat, source: ("./plugins/" + $name)}]' \
     <repo>/.claude-plugin/marketplace.json > "$tmp" && mv "$tmp" <repo>/.claude-plugin/marketplace.json
   ```
5. **Update `<repo>/README.md`** (use the Edit tool, not sed — README structure should be respected, not pattern-matched):
   - In the `## Skills in this marketplace` section, append a new bullet to the existing list:
     `- **<name>** — <plugin description>`
   - In the `## Install` code block, append the install line just before the closing triple-backtick:
     `/plugin install <name>@<MARKETPLACE_NAME>`
   - If either section is missing in the README, surface a warning and ask the user whether to skip the README update or abort.
6. **Validate**:
   - `jq . <repo>/.claude-plugin/marketplace.json > /dev/null`
   - `jq . <repo>/plugins/<name>/.claude-plugin/plugin.json > /dev/null`
   - README contains `<name>` at least twice (once in list, once in install commands).
7. **Commit + push**:
   ```bash
   cd <repo> && git add . && git commit -m "feat: add <name> skill" && git push
   ```
8. **Print install instructions** for other machines / this machine:
   ```
   /plugin marketplace update <MARKETPLACE_NAME>
   /plugin install <name>@<MARKETPLACE_NAME>
   ```
9. **Ask: link the global path to the repo as `<name>`?** Default **no**. Behavior depends on `<kind>` from step 1:
   - **global source** — *"Replace `~/.claude/skills/<name>` with a symlink to `<repo>/plugins/<name>/skills/<name>` so future edits to the repo show up immediately?"* If yes: `rm -rf ~/.claude/skills/<name> && ln -s <repo>/plugins/<name>/skills/<name> ~/.claude/skills/<name>`. Otherwise advise: verify the plugin install works, then delete the local copy to avoid drift.
   - **project source** — *"Create a symlink at `~/.claude/skills/<name>` → `<repo>/plugins/<name>/skills/<name>` so the published version is also available outside this project?"* If yes: `ln -s <repo>/plugins/<name>/skills/<name> ~/.claude/skills/<name>` (only if that path doesn't already exist). **Never** modify the original project-local skill — leave it alone.
   - **explicit source** — skip the question entirely. The user pointed at a free-floating path; we don't know enough about it to suggest a sensible linking action.

## Update mode — execution

0. **Symlink shortcut detection.** Test `[ "$SOURCE_DIR" -ef "<repo>/plugins/<name>/skills/<name>" ]` (bash `-ef` returns true if both paths point to the same inode, transparent through any number of symlink hops). If true, source and target are the same physical folder — rsync would be a no-op, so skip ahead to commit:
   - If `git -C <repo> status --short` is empty → print *"Nothing to publish — source is symlinked to the repo and the repo has no pending changes. Make your edits, then re-run."* and exit.
   - If the only changes are inside `plugins/<name>/` → jump to step 4 (commit-message question) and continue from there.
   - If there are changes elsewhere too → warn, list the unrelated files, and ask whether to include them in this commit (offer `git add plugins/<name>` for a narrow commit, vs `git add .` for everything).

1. Diff: `diff -ruN "$SOURCE_DIR/" <repo>/plugins/<name>/skills/<name>/` — print a short summary (count of changed/added/removed files).
2. If no diff, exit early: *"Nothing to publish — local and repo versions are identical."*
3. Sync: `rsync -a --delete "$SOURCE_DIR/" <repo>/plugins/<name>/skills/<name>/` (the trailing slashes matter — copy *contents*, not the folder itself).
4. Ask for the commit message kind: `feat:` / `fix:` / `refactor:` / `docs:` (default `refactor:`). Append a short summary (extract from the diff or ask).
5. **Do NOT update marketplace.json or README in update mode** — the skill is already listed; metadata changes are a separate concern that the user should do manually if needed.
6. `cd <repo> && git add plugins/<name> && git commit -m "<kind>: update <name>" && git push`.

## Rules

- Never auto-create the marketplace repo itself — if `marketplace.json` is missing, stop and tell the user to bootstrap their marketplace first.
- Never force-push. Never amend.
- Never bake a specific GitHub username, repo path, or author name into the generated files — always read from `marketplace.json` / `gh` / `git config` at runtime.
- Never delete `$SOURCE_DIR` automatically. The symlink question in add-mode step 9 may replace `~/.claude/skills/<name>/` *only if* it is the source (`<kind> = global`).
- If `gh` is not authenticated (`gh auth status` fails), the push step will fail — verify before mutating files.
- Don't run `git push --force-with-lease` or anything that rewrites history. New commits only.
