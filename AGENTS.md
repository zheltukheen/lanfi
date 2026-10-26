# Agent guide

Read [`WARP.md`](WARP.md) for commands, architecture and column/persistence
details, and [`CONTRIBUTING.md`](CONTRIBUTING.md) for workflow expectations.

Quick checks before handing off:

```bash
xcodegen generate
./scripts/lint.sh
xcodebuild test -project LanFi.xcodeproj -scheme LanFi \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./build.sh
```
