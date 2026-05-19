# claude-skills

Whitney's personal Claude Code skills, packaged as a [Claude Code marketplace](https://docs.claude.com/en/docs/claude-code/plugins) so they can be installed on any machine via `/plugin install`.

## Skills in this marketplace

- **bootstrap-xcode-project** — Scaffold a new iOS Xcode project via XcodeGen (`.xcodeproj`, Swift Testing + XCUITest, MVVM folders, optional SwiftData/CoreData/GRDB, SwiftLint, xcconfig credentials, private GitHub repo + CI).

## Install

Inside any Claude Code session:

```
/plugin marketplace add whitney13625/claude-skills
/plugin install bootstrap-xcode-project@whitney-claude-skills
```

The `@whitney-claude-skills` suffix is the marketplace `name` field from `.claude-plugin/marketplace.json` — not the GitHub repo name.

## Update

After pushing changes to this repo:

```
/plugin marketplace update whitney-claude-skills
```

Re-running `/plugin install <name>@whitney-claude-skills` picks up the new version.

## Adding a new skill to the marketplace

1. Create `plugins/<skill-name>/skills/<skill-name>/SKILL.md` (plus `assets/`, `scripts/`, `references/` as needed).
2. Add `plugins/<skill-name>/.claude-plugin/plugin.json`:
   ```json
   {
     "name": "<skill-name>",
     "description": "...",
     "version": "0.1.0",
     "author": { "name": "whitney13625" }
   }
   ```
3. Add a new entry to the `plugins` array in `.claude-plugin/marketplace.json`.
4. Commit, push, then `/plugin marketplace update whitney-claude-skills` and `/plugin install <skill-name>@whitney-claude-skills`.

## Mixing marketplace-installed and local skills

You don't have to put every skill in this repo. Claude Code looks in **both** locations:

- `~/.claude/plugins/marketplaces/<marketplace>/plugins/<plugin>/skills/<skill>/` — installed via `/plugin install`, version-controlled here.
- `~/.claude/skills/<skill>/` — local-only, never pushed.

Use the local path for:
- Experiments / drafts before they're worth syncing.
- Anything machine-specific (contains paths, credentials, hardcoded project names).
- Personal scratch skills you don't want on GitHub.

Use this repo for anything you want to keep across machines or eventually share.

If a skill exists in both locations with the same `name`, the plugin-installed one wins — so don't keep stale copies of marketplace skills under `~/.claude/skills/`.

## License

MIT — see [LICENSE](LICENSE).

## Repo layout

```
.
├── .claude-plugin/
│   └── marketplace.json        # lists the plugins
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/
        │   └── plugin.json     # plugin metadata
        └── skills/
            └── <skill-name>/
                └── SKILL.md    # plus assets/, scripts/, references/ if needed
```
