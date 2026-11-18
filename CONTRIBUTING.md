# Contributing

Thank you for wanting to help.

## Issues, not pull requests

**This project takes issues only.** Bug reports, touchscreen reports and ideas are all welcome, as [issues](https://github.com/crissmoldovan/tactile-mac/issues/new/choose):

- **A bug:** what happened, what you expected, and the output of **Copy diagnostics** (in General), with the serial numbers taken out.
- **A touchscreen:** its model and USB vendor:product ID, and what works and what doesn't. The form says how to find the ID. Reports of touchscreens that work are as useful as those that don't.
- **An idea:** what you'd like Tactile to do, and why.

**Pull requests from outside are closed automatically, with thanks.** If you'd like a change, open an issue that describes it. Code you have written can go in the issue, as a sketch.

Please follow the [code of conduct](CODE_OF_CONDUCT.md). Security problems go privately, as [`SECURITY.md`](SECURITY.md) says.

## Building and testing

You need macOS 14 or later and Xcode 27 or later. The project signs ad hoc by default, so no certificate is needed (README, "Building from source").

```sh
swift test --package-path Packages/TactileKit                     # the package's tests: no hardware, no window
swift build --package-path Packages/TactileKit --build-tests -Xswiftc -warnings-as-errors
xcodebuild -project Tactile.xcodeproj -scheme Tactile -configuration Debug -derivedDataPath build build
swift test --package-path Tools/tactile-probe
swift test --package-path Tools/tactile-input-mode
swift test --package-path Tools/tactile-release
Tools/install-signing-tests.sh                                    # install.sh's and release.sh's signing messages
Tools/release-settings-tests.sh                                   # release.sh's settings and build-number checks
scripts/check-attribution-tests.sh                                # the attribution check and its hooks
```

Run them one at a time: each builds a lot.

## No AI attribution in commits or pull requests

No commit message, pull request title or pull request description may say it was written or co-written by an AI tool. That means no `Co-authored-by:` (or other `...-by:`) line naming Claude, Copilot, ChatGPT, Cursor, Gemini or any other AI tool or its address, no "Generated with" such a tool, no robot-emoji "Generated" footer, no links to Claude Code, no `Claude-Session:` line, and no mention of Claude Code. Human co-authors are welcome, and words like "agent" are fine.

The full list is at the top of `scripts/check-attribution.sh`. To add a tool, add it there and add a case to `scripts/check-attribution-tests.sh`.

**On your machine,** turn on the repository's git hooks once, in your clone:

```sh
git config core.hooksPath .githooks
```

The `commit-msg` hook refuses a commit whose message credits an AI tool, and the `pre-push` hook refuses a push that carries one, even if it was committed with `--no-verify`. To fix a refused commit, use `git commit --amend` for the last one, or `git rebase -i` and "reword" for older ones.

**In CI,** the `no-agent-attribution` check runs on every push and every pull request. It checks every new commit, and the pull request's title and description, and fails if any of them credits an AI tool.

## Forks

Tactile is under the GPL-3.0, so you may fork it. The name and the icon are not part of that licence: a fork needs its own (see [`TRADEMARKS.md`](TRADEMARKS.md)).

A fork's builds don't update themselves. Only the official build does: bundle identifier `com.crissmoldovan.tactile`, signed with the Developer ID of team 75K3LTUM8A. Any other build asks no site, and says "Updates are off in this build of Tactile." So an official release never replaces a fork.

If your fork should update itself from a site of its own, change all of these:

1. **The bundle identifier,** `PRODUCT_BUNDLE_IDENTIFIER` in `Tactile.xcodeproj`. The code uses `com.crissmoldovan.tactile` as its log subsystem too; yours can follow.
2. **The update site and keys,** in `Config/Updates.xcconfig` (or your `Config/Signing.local.xcconfig`): `TACTILE_UPDATE_BASE_URL`, an https origin you run, and `TACTILE_UPDATE_KEYS`, your own Ed25519 public keys (`Tools/tactile-release` makes a key). Put the same keys in `UpdateTrust.productionKeys`.
3. **The official identity,** in `Packages/TactileKit/Sources/TactileUpdates`: `OfficialBuild.bundleIdentifier`, and the bundle identifier and team in `SecurityCodeSignatureCheck.developerIDRequirement`. This is what decides whether a build updates itself at all, and what every update must be signed with.
4. **Your site,** which must answer as [`docs/updates-contract.md`](docs/updates-contract.md) describes. Tactile's own site is not in this repository.

Skip all of that and your builds simply don't update themselves.
