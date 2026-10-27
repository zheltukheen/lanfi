# Contributing to LanFi

Thanks for helping make LanFi the best native, open-source Wi-Fi analyzer on
macOS.

## Development setup

Requirements: macOS 13+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/zheltukheen/lanfi.git
cd lanfi
xcodegen generate
open LanFi.xcodeproj
```

`project.yml` is the source of truth for the Xcode project. If you add, move or
delete source files, run `xcodegen generate` and commit the regenerated
`LanFi.xcodeproj/project.pbxproj`.

## Build and test

```bash
./build.sh                       # universal Release build
xcodebuild test \
  -project LanFi.xcodeproj \
  -scheme LanFi \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
./scripts/lint.sh
```

## Code guidelines

- Keep scanning and parsing off the main thread; UI state is `@MainActor`.
- Pure logic (scoring, overlap math, IE parsing) belongs in a testable type
  without CoreWLAN or SwiftUI imports.
- Prefer semantic colors and standard controls; support light and dark mode.
- Do not add analytics, telemetry, or third-party SDKs without prior discussion.
- Add tests for scoring, parsing and export changes.
- Update `CHANGELOG.md` under `## Unreleased`.

## Commits and pull requests

Use conventional prefixes where possible: `feat:`, `fix:`, `perf:`, `docs:`,
`test:`, `ci:`, `chore:`. Keep pull requests focused. Describe the user-visible
change, how it was verified, and include a screenshot for UI changes.

By contributing you agree that your contribution is licensed under the MIT
License in this repository.

## Automatic push

`scripts/autopush.sh` can push completed commits automatically. Install the
repository hook with:

```bash
./scripts/autopush.sh --install-hook
```

Use `--watch` for a debounced working-tree watcher, or `AUTOPUSH_DRY_RUN=1` to
preview. The hook never force-pushes and refuses obvious credentials.


## Contributions and licensing

LanFi is source-available under FSL-1.1-ALv2. By submitting a pull request you
confirm that you have the right to contribute the code and grant the project
maintainers permission to distribute it under the current license and future
license versions. Significant contributions may require a signed contributor
license agreement; maintainers will ask before merging.
