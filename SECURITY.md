# Security

## Reporting a problem

Please report a security problem privately, through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**, or go straight to [a new private report](https://github.com/crissmoldovan/tactile-mac/security/advisories/new). Only the maintainers can read it. Please don't open a public issue for it.

Say what you found, which version of Tactile and macOS, and how to see it happen. You'll get an answer there.

## What matters most

Tactile clicks, scrolls and presses shortcuts for you, with Accessibility access, and it replaces itself when it updates. So the updater matters most. Reports about these are especially welcome:

- anything that makes Tactile install an update the maintainer didn't build and sign;
- anything that lets another program use Tactile's Accessibility or Input Monitoring access;
- anything that reaches beyond the touchscreens Tactile reads.

## How updates are protected

- **The keys are held privately.** The private half of the update key and the Developer ID's key are kept on the maintainer's Mac, in its keychain, with a backup kept apart from it. Neither has ever been in this repository. Only the update key's public half is here, built into every copy.
- **Every update is checked by the app itself,** before anything is installed: its size and SHA-256; an Ed25519 signature from one of the update keys built into the app; and, unpacked, an app signed with the official Developer ID under Tactile's bundle identifier, and the version offered. Any failure stops the update and deletes the download. The website only passes the files on.
- **No secret is in the app.** It knows only the site's address and the public keys.
- **Only the official build updates itself.** A build from source, or a fork, asks no site.

[`docs/updates-contract.md`](docs/updates-contract.md) has the details, and [`Tools/RELEASING.md`](Tools/RELEASING.md) how a new update key would replace an old one.

## Supported versions

Only the newest release gets fixes. The official build updates itself, so please update before you report.
