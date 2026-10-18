# XcodeGen `project.yml` cheatsheet

Load this only when the generated `project.yml` fails to parse or you need a field not present in the template. Full docs: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

## Top-level keys

- `name` — project name (matches `.xcodeproj` basename).
- `options` — global options. Useful subfields:
  - `bundleIdPrefix: com.example` — used when a target omits an explicit `PRODUCT_BUNDLE_IDENTIFIER`.
  - `deploymentTarget.iOS: "26.0"`
  - `createIntermediateGroups: true` — mirrors folder structure as Xcode groups.
  - `generateEmptyDirectories: true` — keeps empty folders like `Views/` visible.
- `settings.base` — build settings applied to every target. Common entries:
  - `SWIFT_VERSION: "6.2"`
  - `SWIFT_STRICT_CONCURRENCY: complete` (Swift 6 mode)
- `packages` — Swift Package dependencies, keyed by name:
  ```yaml
  packages:
    GRDB:
      url: https://github.com/groue/GRDB.swift
      from: 7.0.0
  ```
- `targets` — map of target name → spec (see below).
- `schemes` — explicit scheme definitions; XcodeGen also auto-generates one per target if omitted.

## Target spec

```yaml
targets:
  MyApp:
    type: application            # bundle.unit-test | bundle.ui-testing | framework | ...
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: MyApp              # folder added recursively
      - path: MyApp/Generated    # multiple paths allowed
        optional: true
    resources:
      - path: MyApp/Assets.xcassets
    dependencies:
      - target: MyAppCore        # other target in this project
      - package: GRDB            # entry in top-level `packages`
      - sdk: CoreData.framework  # system framework
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
    info:                         # merged with GENERATE_INFOPLIST_FILE output (explicit file wins)
      path: MyApp/Info.plist
      properties:
        CFBundleShortVersionString: "1.0"
    preBuildScripts:              # or postBuildScripts / postCompileScripts
      - name: SwiftLint
        script: |
          if which swiftlint >/dev/null; then
            swiftlint
          else
            echo "warning: SwiftLint not installed"
          fi
        basedOnDependencyAnalysis: false
```

## Test targets

- Unit tests: `type: bundle.unit-test`
- UI tests: `type: bundle.ui-testing`
- Both should declare `dependencies: [{ target: <app target> }]`.
- Swift Testing requires no special config — XCTest target hosts it automatically when the SDK is iOS 18+.

## Common gotchas

- Bundle ID for test targets **must** differ from the app's (append `.tests`, `.uitests`).
- `GENERATE_INFOPLIST_FILE: YES` only injects Apple's **curated** `INFOPLIST_KEY_*` settings — custom `INFOPLIST_KEY_<Name>` build settings are silently dropped. To ship custom Info.plist keys, also set `info.path` + `info.properties` (e.g. `MY_KEY: "$(MY_KEY)"`); Xcode merges that file with the generated content, and the explicit file's keys win.
- `createIntermediateGroups: true` is almost always what you want — without it, nested folders collapse into a single group named with the full path.
- Run `xcodegen generate` from the directory containing `project.yml`. Cwd matters.
- After changing `project.yml`, regenerate and re-open the `.xcodeproj` — Xcode does not hot-reload it.

## Sanity checks

```bash
xcodegen generate --quiet
xcodebuild -list -project {{ProjectName}}.xcodeproj   # confirms schemes
xcodebuild -showBuildSettings -scheme {{ProjectName}} | grep -E '(SWIFT_VERSION|IPHONEOS_DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER)'
```
