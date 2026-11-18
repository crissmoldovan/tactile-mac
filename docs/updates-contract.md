# The updates contract

What the official build of Tactile, its release script (`Tools/release.sh`) and its website (tactilemac.com) agree on, so that Tactile can update itself safely. The code cites this file as "the updates contract".

The idea in one line: **the website is only a courier.** Tactile checks every update itself, against keys and a signing identity built into it, before it installs anything. No token, password or other secret is in the app.

## Who asks, where, and with which keys

- **Who asks.** Only the official build: bundle identifier `com.crissmoldovan.tactile`, whose own code signature (`SecCodeCopySelf`) satisfies the requirement in check 4 below. Any other build, ad hoc or a fork's, asks no site, and **Check for Updates…** and General say "Updates are off in this build of Tactile." (`OfficialBuild`, `UpdateAvailability`).
- **Where it asks.** The Info.plist key `TactileUpdateBaseURL`, set by the build setting `TACTILE_UPDATE_BASE_URL` in `Config/Updates.xcconfig`: `https://tactilemac.com`. It must be an https origin. The user default of the same name can point one installed copy at another https origin, or at `http://localhost` for a website run locally.
- **Which keys it trusts.** The Info.plist key `TactileUpdateKeys`, set by the build setting `TACTILE_UPDATE_KEYS` in the same file: `<keyId>:<base64 public key>`, several separated by spaces, each keyId once. Today it is `k1` alone. `UpdateTrust.productionKeys` holds the same keys, for a build whose Info.plist names none.
- **Unusable settings fail closed.** A site or a key list that is there but can't be used (one bad key entry is enough) turns updates off, as for a build that isn't official. `release.sh` reads the built app's Info.plist with the app's own code before anything is published.
- **When.** One check a minute after launch, then one every 24 hours, while **Check for updates automatically** (in General, on by default) is on; a failed one is tried again after an hour. And on **Check for Updates…** in the menu. A failed automatic check says nothing; a failed manual one says why, in a line.

## A release

Made by `Tools/release.sh` on the maintainer's Mac, from a commit tagged `mac-v<version>`, and published as a GitHub release of `crissmoldovan/tactile-mac` (see [`Tools/RELEASING.md`](../Tools/RELEASING.md)).

- **Version:** the project's `MARKETING_VERSION`, `<major>.<minor>.<patch>`.
- **Build:** `git rev-list --count HEAD` at the tagged commit, plus 500 (`TACTILE_BUILD_OFFSET`). It only ever grows: `release.sh` refuses a build that isn't above the newest release's, or above the build the website serves now.
- **Signing:** Developer ID Application, team 75K3LTUM8A, hardened runtime, secure timestamp; notarized by Apple, and the ticket stapled.
- **Four files:**
  - `Tactile-<version>.zip`: the update, `ditto -c -k --keepParent` of the stapled app;
  - `Tactile-<version>.dmg`: the first install (the app and an Applications link), itself signed, notarized and stapled;
  - `update.json`, below;
  - `SHA256SUMS`, of the zip and the DMG.

`update.json`, with exactly these keys in this order:

```json
{ "schema": 1, "version": "0.7.0", "build": 501, "minimumSystemVersion": "14.0",
  "publishedAt": "2026-11-18T10:00:00Z", "notes": "One paragraph per line, plain text.",
  "archive": { "name": "Tactile-0.7.0.zip", "size": 7340032, "sha256": "<hex>",
               "signature": "<base64 Ed25519 over the zip's bytes>", "keyId": "k1" },
  "dmg": { "name": "Tactile-0.7.0.dmg", "size": 7864320, "sha256": "<hex>" } }
```

## The update key

- **Ed25519**, as CryptoKit's `Curve25519.Signing`.
- Keys are written as standard base64, with padding, of their 32-byte raw representation. A signature is standard base64 of its 64 bytes, made over the exact bytes of the zip.
- `keyId` names the key a release is signed with, so the app can trust a list of keys, and a release signed with an old key can ship the app that trusts a new one.
- The private half is kept in the release Mac's login keychain (a generic password, service `Tactile update signing key`, account the keyId), with a backup elsewhere. It never enters this repository, and `tactile-release` never prints it. `Tools/RELEASING.md` says how a new key replaces an old one.

## The website's answers

The website's source is not in this repository. It reads the GitHub releases of one repository with a token it keeps on the server; the token never appears in an answer, a redirect or a log. It takes as the newest release the highest `mac-vX.Y.Z` that isn't a draft, carries all four files, and has an `update.json` that parses and agrees with its tag. It serves only files of the repository it reads.

- **`GET /api/mac/update?version=<version>&build=<build>`**: the newest release, as the app needs it. The query is for the site's logs; the answer doesn't depend on it. The app decides.

  ```json
  { "version": "0.7.0", "build": 501, "minimumSystemVersion": "14.0", "publishedAt": "...", "notes": "...",
    "archive": { "url": "https://tactilemac.com/api/mac/archive/0.7.0", "size": 7340032, "sha256": "<hex>",
                 "signature": "<base64>", "keyId": "k1" } }
  ```

  Every field is required, and fields not named here are ignored. 404 means no release yet, which the app doesn't count as a failure. 503 (not set up) and 502 (GitHub failed) come with a short JSON `error`. Answers are cached for up to 5 minutes.
- **`GET /api/mac/archive/<version>`**: that release's zip, as a redirect to the short-lived address GitHub gives for it. The app follows a redirect only to `objects.githubusercontent.com` or `release-assets.githubusercontent.com`.
- **`GET /download`**: the newest DMG, for the Download button. **`GET /api/mac/latest`**: its version, size and minimum macOS, for the page.

## Before installing

When the menu offers **Update to <version>…** (newer by version, then by build) and the person chooses it, Tactile shows the notes. On **Install and Relaunch**:

- **Where it runs from.** Tactile must not be running translocated, and the folder it is in must be writable by this account.

Then the checks, in this order. Any failure stops the update, deletes the download and says why (`UpdateCheck`, `UpdateVerifier`):

1. The answer's `archive.url` is on the site's origin: the same scheme, host and port.
2. The download, into `~/Library/Caches/com.crissmoldovan.tactile/Updates/`, has exactly `archive.size` bytes, and its SHA-256 is `archive.sha256`.
3. `archive.signature` verifies over those bytes with the trusted key named by `archive.keyId`. A key the app doesn't trust is a failure.
4. Unpacked with `ditto -x -k`, the download holds one `Tactile.app` and nothing else, and its code signature is valid (strict, all architectures, nested code included) and satisfies:

   ```
   anchor apple generic and identifier "com.crissmoldovan.tactile"
     and certificate 1[field.1.2.840.113635.100.6.2.6] exists
     and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
     and certificate leaf[subject.OU] = "75K3LTUM8A"
   ```

   That is: Apple's anchor, Tactile's bundle identifier, a Developer ID certificate, and the official team.
5. Its `CFBundleShortVersionString` and `CFBundleVersion` are the answer's, and newer than the running app's.

## Installing

Tactile writes a small helper script into the update folder, starts it detached, and quits the ordinary way, letting the touchscreens go. The helper waits for Tactile to end, moves the new app next to the old one, moves the old one aside, moves the new one into its place and opens it. It removes the old copy only once the new one has started and is still running a moment later. If a step fails, it puts the old app back and opens that.

Accessibility and Input Monitoring survive an update, because the bundle identifier and the Developer ID stay the same.
