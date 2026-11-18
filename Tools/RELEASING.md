# Releasing Tactile

This is how the official releases are made. Only the maintainer can make one: it needs the Developer ID, the notarization profile and the update key, which are held privately and never enter this repository.

A release is made on the maintainer's Mac by `Tools/release.sh`. It builds Tactile from a tagged commit, signed with the Developer ID. It has Apple notarize it and signs the update with Tactile's update key. Then it publishes a GitHub release of `crissmoldovan/tactile-mac`, or of the repository `TACTILE_RELEASE_REPO` names (below). The website (tactilemac.com) reads the newest release, offers it to installed copies, and serves its DMG from the Download button.

Only the official build updates itself: Tactile's bundle identifier, signed with the Developer ID of team 75K3LTUM8A. A build signed any other way, ad hoc as the project signs by default, or a fork's, asks no site and says "Updates are off in this build of Tactile."

The formats (asset names, `update.json`, the key and the signature) and the checks the app makes are fixed by the updates contract, [`docs/updates-contract.md`](../docs/updates-contract.md).

## Once, before the first release

The maintainer does these steps in their own terminal. No password or private key goes into a file or into the repository.

1. **The notarization profile.** Make an app-specific password at [appleid.apple.com](https://appleid.apple.com) (Sign-In and Security, App-Specific Passwords), then run:

   ```
   xcrun notarytool store-credentials tactile-notary --apple-id <your Apple ID> --team-id 75K3LTUM8A
   ```

   It asks for the app-specific password and keeps it in the login keychain. To check it: `xcrun notarytool history --keychain-profile tactile-notary`.

2. **The update key.** `k1` was made on 17 November 2026; its public key is

   ```
   IpKoBBLRNGZ8WqpbNod6gXQdjESJc0xYOjHdBUwbxYI=
   ```

   Do not make it again: `keygen` refuses when the key exists, and a new key would not be trusted by the copies already installed. For the record, it was made with:

   ```
   swift run --package-path Tools/tactile-release tactile-release keygen --key-id k1
   ```

3. **Back up the update key** into your password manager. This copies the private half to the clipboard without showing it:

   ```
   security find-generic-password -s 'Tactile update signing key' -a k1 -w | pbcopy
   ```

   Paste it into a new entry, "Tactile update signing key k1", then clear the clipboard with `pbcopy < /dev/null`. If you use a clipboard history app, remove it there too.

   Why it matters: every installed Tactile checks an update against the public keys built into it. If the private key is lost, no update can be signed with `k1` again. Copies that trust only `k1` then can't update themselves, and each needs the DMG installed by hand.

4. **GitHub.** `gh auth status` should show you signed in, with access to the release repository, `crissmoldovan/tactile-mac` unless `TACTILE_RELEASE_REPO` names another (otherwise run `gh auth login`).

5. **The Developer ID.** The certificate "Developer ID Application: CRISTIAN MOLDOVAN (75K3LTUM8A)" must be in the login keychain (`security find-identity -v -p codesigning` lists it). The first time `release.sh` signs with it, macOS may ask whether `codesign` may use its key. Choose **Always Allow**: a release signs several times.

The app must also trust the key it is updated with. The official build reads its trusted public keys, by keyId, from its Info.plist, where the build setting `TACTILE_UPDATE_KEYS` puts them (`k1:<public key>`, more keys separated by spaces). The site it asks comes the same way from `TACTILE_UPDATE_BASE_URL` (`https://tactilemac.com`). Both are set in `Config/Updates.xcconfig`; the same keys are also in `UpdateTrust.productionKeys`, which a test keeps in step with it. A value there that can't be used (a site that isn't an https origin, or any key entry that isn't `<id>:<base64 of 32 bytes>`, or an ID given twice) turns the build's updates off. `release.sh` reads the built app's Info.plist with the app's own code (`tactile-release check-settings`), and refuses a build whose Info.plist doesn't trust the key it signs with, under its keyId, or doesn't ask `https://tactilemac.com`.

## Where releases go, and the build number

Two settings, both read from the environment when `release.sh` runs:

- `TACTILE_RELEASE_REPO`: the GitHub repository to publish to, as `owner/name`. Unset, it is `crissmoldovan/tactile-mac`. The website must read releases from the same repository.
- `TACTILE_BUILD_OFFSET`: a whole number added to `git rev-list --count HEAD` to make the build number. Unset, it is **500**. This repository's history starts at one commit, and the last build released before it was 471 (0.6.2), so the offset keeps every build above that one: the first is 501. Leave it unset, or keep the same value for every release, so builds only ever grow.

`release.sh` refuses a value that isn't `owner/name`, or a whole number, before it builds anything. In a real run it also refuses a build number that isn't above either of these:

- the build in the `update.json` of the release repository's newest `mac-v<version>` release (skipped when the repository has no release at all);
- the build the website serves now, the `build` in `curl -s https://tactilemac.com/api/mac/update`. This is what installed copies compare with, wherever it was released from, so it also covers a repository's first release. If the site can't be reached, or its answer holds no build, `release.sh` stops too.

`--allow-first-build` skips the second check, with a loud warning. Use it only when the site serves no release at all (it answers 404). A dry run makes the second check and reports it, without stopping.

## Cutting a release

1. Raise `MARKETING_VERSION` in `Tactile.xcodeproj` (target Tactile, General, Version; both configurations change together). Merge that to `main` as usual.
2. On `main`, up to date and clean, tag the commit and push the tag:

   ```
   git tag -a mac-v0.7.0 -m "Tactile 0.7.0"
   git push origin mac-v0.7.0
   ```

3. Write the release notes in a file outside the repository (the tree must stay clean), for example `$TMPDIR/notes-0.7.0.txt`. Use plain text, one paragraph per line. Tactile shows them before it updates, and they become the GitHub release's text.
4. If you like, rehearse it: `Tools/release.sh --dry-run --notes "$TMPDIR/notes-0.7.0.txt"`. A dry run builds, signs and checks everything, but notarizes nothing and publishes nothing.
5. Release:

   ```
   Tools/release.sh --notes "$TMPDIR/notes-0.7.0.txt"
   ```

   It takes 10 to 20 minutes, most of it waiting for Apple's notary service. At the end it names its folder in `$TMPDIR`: the four published files, the logs, and the archive with its dSYMs. Keep the archive if you want to read crash reports from that build.
6. Within about 10 minutes, `curl -s https://tactilemac.com/api/mac/update` shows the new version: the site keeps GitHub's release list for up to 5 minutes, and its CDN keeps each answer for up to 5 more.

The build number is `git rev-list --count HEAD` at the tagged commit, plus `TACTILE_BUILD_OFFSET`. It always increases (`release.sh` refuses one that isn't above the newest release's, or the site's) and is never edited by hand.

What is built is the tagged commit itself, exported with `git archive` in the same run, so nothing uncommitted can get into a release.

## When a step fails

Nothing is published until the last step, so once the cause is fixed, run it again. Each run starts from scratch in a new folder. A submission to Apple that was not used does no harm.

| It says | What to do |
|---|---|
| The working tree is not clean | Commit or stash the changes. Notes files belong outside the repository. |
| HEAD is not tagged `mac-v<version>`, or the tag is on another commit | Tag the commit you mean to release (see above). If a tag was made on the wrong commit and **not yet released**, delete it (`git tag -d mac-vX.Y.Z`, and `git push origin :refs/tags/mac-vX.Y.Z` if it was pushed) and tag again. Never move the tag of a published release. |
| The tag and the project's version must agree | Either the tag or `MARKETING_VERSION` is wrong: fix the one that is. |
| The signing identity is not in the keychain | Restore the Developer ID Application certificate and its key to the login keychain (from your backup, or Xcode, Settings, Accounts, Manage Certificates). |
| The notarytool profile is missing, or Apple did not accept it | Run the `store-credentials` command above again. App-specific passwords stop working when revoked or when the Apple ID password changes. |
| gh is not signed in, or can't read the repository | `gh auth login`, with the account that owns the release repository (`crissmoldovan/tactile-mac`, or `TACTILE_RELEASE_REPO`). |
| There is already a release `mac-v<version>` | That version is out. Raise `MARKETING_VERSION` for a new one. |
| GitHub does not have the tag at this commit | `git push origin mac-v<version>`. |
| Could not read update key `k1` | The keychain lost it. Put the backup back (below). Never make a new `k1`. |
| codesign was still waiting after 120 seconds | macOS is showing a Keychain prompt for the Developer ID key. Answer it with Always Allow, then run again. |
| No secure timestamp | `codesign` could not reach Apple's timestamp server. Check that the Mac is online, then run again. |
| The Release build failed | Read the log it names (in the run's `logs/`). |
| The app's update settings won't do for a release signed with `k1` | The app's Info.plist doesn't trust that key under that keyId, can't be read whole (updates would be off), or asks another site. Fix `TACTILE_UPDATE_KEYS` or `TACTILE_UPDATE_BASE_URL` in `Config/Updates.xcconfig` (and `UpdateTrust.productionKeys` to match), then commit, tag and release that commit. |
| Build N is not above build M of mac-vX.Y.Z | The build number would go backwards. Check that `TACTILE_BUILD_OFFSET` is unset or 500, and that `TACTILE_RELEASE_REPO` names the repository you meant. |
| Build N is not above build M, which the site serves now | The same: installed copies would not take it as newer. Check `TACTILE_BUILD_OFFSET`. |
| Could not read the build the site serves now | Check that the Mac is online and that `curl -s https://tactilemac.com/api/mac/update` answers with a `build`. Only if the site serves no release at all, run again with `--allow-first-build`. |
| Apple did not accept the app or the disk image | Its log is in the run's `logs/` (or `xcrun notarytool log <id> --keychain-profile tactile-notary`). Fix what it names. If that needs a code change, it is a new commit: move the unreleased tag to it (as in the row above), then run again. |
| Publishing failed part-way (exit 2) | The release may exist with files missing; the website ignores a release without all four. Either finish it with `gh release upload mac-vX.Y.Z --repo <the release repository> --clobber <the files it names>`, or delete it (`gh release delete mac-vX.Y.Z --repo <the release repository> --yes`, which keeps the tag) and run again. `release.sh` prints both commands with the repository filled in. |
| `TACTILE_RELEASE_REPO` or `TACTILE_BUILD_OFFSET` is refused | Write the repository as `owner/name` and the offset as a whole number, or unset them for the defaults. |

## The update key

- **Where it is:** the login keychain, as a generic password with service `Tactile update signing key` and account the keyId (`k1`). Only `/usr/bin/security` reads it, without a prompt. `tactile-release` never prints it or writes it to a file.
- **Putting a backup back** (a new Mac, or a reset keychain): copy the key from your password manager, then run

  ```
  pbpaste | swift run --package-path Tools/tactile-release tactile-release import --key-id k1
  pbcopy < /dev/null
  ```

  It prints the public key, which must be `IpKoBBLRNGZ8WqpbNod6gXQdjESJc0xYOjHdBUwbxYI=` for `k1`.
- **Changing to a new key** (`k1` is retired, or at risk):
  1. Make `k2` with `keygen --key-id k2` and back it up.
  2. Add `k2`'s public key beside `k1`'s: in `TACTILE_UPDATE_KEYS` in `Config/Updates.xcconfig`, as `k1:<k1's key> k2:<k2's key>` (a `//` in a key is written `/$()/`), and in `UpdateTrust.productionKeys`. One bad entry turns updates off, and `release.sh` refuses it.
  3. Release that version signed with `k1`, as usual.
  4. Once the installed copies have that version, sign releases with `k2`, using `release.sh --key-id k2`.

  If `k1` is lost before a release trusting `k2` has shipped, the copies that trust only `k1` can't update. Install the new DMG by hand on each Mac.
- **Other commands:** `tactile-release public-key --key-id k1` prints the public key. `tactile-release --help` lists the rest.

## The website

Installed copies don't know where releases live: they ask tactilemac.com, which reads the GitHub releases of one repository, named in the site's own settings (its source is not in this repository). The site serves only assets of the repository it reads. So when releases move to another repository, the site is switched only once that repository has a complete release; until then it keeps serving the old one, and `release.sh`'s comparison with the site's build still holds.
