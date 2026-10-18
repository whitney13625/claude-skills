# Self-hosted macOS runner

Facts learned bringing up an organization-level runner on a Mac for GitHub Actions. `<owner>` is the GitHub organization that owns the repo.

## Org vs personal account

- An organization runner is registered once and shared by every repo in that organization (labels `self-hosted, macOS, ARM64`). No per-repo registration.
- A personal-account repo cannot use an organization runner: personal-account self-hosted runners are repo-scoped. Either move the repo into the organization, register a separate runner for that one repo on the CI Mac, or use GitHub-hosted runners.

## Check it

- `gh api orgs/<owner>/actions/runners -q '.runners[] | "\(.name) \(.status) busy=\(.busy) \([.labels[].name] | join(","))"'`. This needs the `admin:org` token scope (`gh auth refresh -h github.com -s admin:org`).
- If it is **offline**, CI jobs sit in `queued` forever. On the CI Mac, go to the folder the runner was installed in (`./svc.sh status`, `./svc.sh start`). `launchctl list | grep actions.runner` must show a PID in the first column; a `-` means launchd started it and it exited. `./run.sh` in a terminal is a quick foreground check (`Listening for Jobs`).

## Register one

- No `gh` needed on the CI Mac: open `https://github.com/organizations/<owner>/settings/actions/runners/new`, choose macOS / ARM64, and run the Download and Configure commands it shows on the CI Mac.
- Install it as a service with `./svc.sh install && ./svc.sh start` instead of `./run.sh`, so it survives reboots.

## Keep it healthy

- The CI Mac must not sleep (closing the lid sleeps it even on power): `sudo pmset -a disablesleep 1`, or "Prevent automatic sleeping on power adapter when the display is off". A job interrupted by sleep shows as `cancelled`.
- It needs Homebrew at `/opt/homebrew`; the `prepare-ios` action installs `xcodegen`, `jq` and `swiftlint` with it.
- It needs an Xcode of major `CI_MAJOR` installed as `/Applications/Xcode*.app`, with the matching iOS simulator runtime. The action picks the newest one itself, so `xcode-select` does not matter, and installing a newer major Xcode does not change what CI tests against.
- Persistent DerivedData lives at `~/ci-cache/<runner name>/<owner>/<repo>/xcode-<version>/`. Folders for old Xcode versions are not pruned automatically; delete them after an Xcode upgrade if disk runs low (`du -sh ~/ci-cache/*/*/*/*`).
- Several runners on one Mac each get their own cache folder (keyed by runner name), so two jobs never build into the same DerivedData at once.
