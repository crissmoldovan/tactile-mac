#!/usr/bin/env bash
# Makes a release of Tactile from the tagged commit: builds it signed with the Developer ID, has it
# notarized, signs the update with the update key, and publishes it as a GitHub release.
# `Tools/release.sh --help` says what it does; Tools/RELEASING.md says when and how.
set -euo pipefail

readonly BUNDLE_ID="com.crissmoldovan.tactile"
readonly TEAM_ID="75K3LTUM8A"
readonly IDENTITY="Developer ID Application: CRISTIAN MOLDOVAN ($TEAM_ID)"
# The GitHub repository releases are published to, unless TACTILE_RELEASE_REPO names another.
readonly DEFAULT_RELEASE_REPO="crissmoldovan/tactile-mac"
# Added to the commit count to make the build number, unless TACTILE_BUILD_OFFSET says otherwise. This
# repository's history starts at one commit, and the last build released before it was 471 (0.6.2):
# with 500, its first build is 501, and builds only ever grow.
readonly DEFAULT_BUILD_OFFSET=500
readonly NOTARY_PROFILE="tactile-notary"
# The site the official build must ask for updates: its Info.plist's TactileUpdateBaseURL is checked
# against it (from Config/Updates.xcconfig's TACTILE_UPDATE_BASE_URL).
readonly UPDATE_SITE="https://tactilemac.com"
# What the site serves now: its answer's build is the newest build installed copies know of.
readonly UPDATE_ANSWER_URL="$UPDATE_SITE/api/mac/update"
# The code requirement the updater checks an update's app against (the updates contract, step 4):
# Developer ID (the intermediate's and the leaf's markers), Cristian's team, this bundle identifier.
readonly APP_REQUIREMENT='anchor apple generic and identifier "com.crissmoldovan.tactile" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "75K3LTUM8A"'
# The same for the disk image, which has no bundle identifier.
readonly DMG_REQUIREMENT='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "75K3LTUM8A"'
readonly SIGNING_WAIT_SECONDS=120
readonly LOCK_PATH="${HOME:?HOME is not set}/Library/Caches/$BUNDLE_ID.release.lock"

usage() {
    cat <<'EOF'
usage: Tools/release.sh --notes <file> [--key-id <id>] [--allow-first-build]
       Tools/release.sh --dry-run [--notes <file>] [--key-id <id>] [--allow-first-build]
       Tools/release.sh --help

Makes a release of Tactile from the commit checked out here and publishes it as a GitHub release
of crissmoldovan/tactile-mac, or of the repository TACTILE_RELEASE_REPO names (below). Run it from
anywhere: it works on the checkout it is in. The commit must be tagged mac-v<version>, where
<version> is the project's MARKETING_VERSION, and the working tree must be clean.
Tools/RELEASING.md has the one-time steps and what to do when a step fails.

What it does, in order; any failure stops it, and nothing is published before the last step:
  1. Checks: the working tree is clean; HEAD is tagged mac-v<version>; the Developer ID identity
     is in the keychain; the notarytool profile tactile-notary works; gh is signed in and can read
     the repository; there is no release mac-v<version> yet, and GitHub has the tag at this
     commit; the build number is above the build of the repository's newest release (read from
     its update.json; skipped when the repository has no release yet), and above the build
     https://tactilemac.com/api/mac/update serves now (skipped only with --allow-first-build);
     the update key (--key-id) is in the keychain, and the Developer ID key can sign.
  2. Exports the commit with git archive and builds that, so only what is committed is built: an
     xcodebuild archive, Release, signed with the Developer ID (hardened runtime, secure
     timestamp), build number git rev-list --count HEAD plus TACTILE_BUILD_OFFSET (500). The signing
     settings are all given here: the project itself signs ad hoc, and a release never depends
     on the project's signing or on the git-ignored Signing.local.xcconfig. When two valid
     certificates have that name (after a renewal), it signs with the one that expires last.
  3. Checks the app: codesign --verify --deep --strict, the code requirement the updater checks,
     identifier, version and build, the hardened runtime, the secure timestamp, no
     get-task-allow; and, in its Info.plist, read as the app reads it (tactile-release
     check-settings), that it trusts the update key under its keyId and asks
     https://tactilemac.com.
  4. Notarizes the app and staples it; packs Tactile-<version>.zip (ditto, as the updater
     unpacks it) and checks what is inside; makes Tactile-<version>.dmg (the app and an
     Applications link), signs, notarizes and staples it, and checks what is inside.
  5. Signs the zip with the update key and checks the signature; writes update.json and
     SHA256SUMS, and checks them against the files.
  6. Publishes release mac-v<version> (not a draft) with the four files and the notes.

Everything is made in a new folder in $TMPDIR, named at the end: the four files in release/, the
logs in logs/, and the archive (with its dSYMs, for reading crash reports) as Tactile.xcarchive.
Nothing is written into the repository or its build/ folder.

  --notes <file>   the release notes: plain text, one paragraph per line (blank lines are left
                   out). They go into update.json (Tactile shows them before updating) and the
                   GitHub release. Required, except with --dry-run.
  --key-id <id>    the update key to sign with (default k1). The app must trust it.
  --dry-run        build, sign and check, and write the four files, but notarize nothing and
                   publish nothing. The tag check is reported, not required; the notarytool and
                   GitHub checks are skipped; an app that does not trust the update key, and a
                   build not above the site's, are reported. A dry run's zip and DMG are not
                   notarized: never publish them.
  --allow-first-build
                   don't compare the build with the one https://tactilemac.com serves now. Only
                   for a release when the site serves none at all. It warns loudly: installed
                   copies may not take a build that isn't above theirs.
  -h, --help       this text.

Environment:
  TACTILE_RELEASE_REPO   the GitHub repository to publish to, as owner/name (default
                         crissmoldovan/tactile-mac). The website must read releases from the
                         same repository: its TACTILE_RELEASES_REPO.
  TACTILE_BUILD_OFFSET   a whole number added to git rev-list --count HEAD to make the build
                         number (default 500). This repository's history starts at one commit;
                         the offset keeps its builds above the last build released before it
                         (471, for 0.6.2), so its first is 501. Keep it: builds must only grow.

If codesign has not finished after 120 seconds while checking the Developer ID key, macOS is
probably showing a Keychain prompt for that key: it stops and says so. Answer the prompt with
Always Allow, then run it again.

One run at a time: the lock is ~/Library/Caches/com.crissmoldovan.tactile.release.lock.

Exit status:
  0  released (with --dry-run: built, signed and checked)
  1  stopped before publishing: a bad option, a failed check, build or step. Nothing was published.
  2  publishing failed or was interrupted part-way: the release may exist with files missing.
     What to do was printed.
EOF
}

# --- Output -------------------------------------------------------------------------------------

explained=false   # a message has said why it stopped
step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
would() { printf '    [dry run] would %s\n' "$*"; }
warn() { printf '    warning: %s\n' "$*" >&2; }
fail() {  # stop (exit 1; exit 2 once publishing has started, see on_exit)
    explained=true
    printf '\nrelease.sh: %s\n' "$1" >&2
    shift
    local line
    for line in "$@"; do printf '    %s\n' "$line" >&2; done
    exit 1
}
reported=()       # in a dry run: what a real run would have stopped at
not_required() {  # a check a real run needs: a real run stops here, a dry run reports it and goes on
    if $dry_run; then
        local first="$1" line
        shift
        warn "$first"
        for line in "$@"; do printf '             %s\n' "$line" >&2; done
        info "A real run stops here; this dry run goes on."
        reported+=("$first")
    else
        fail "$@"
    fi
}

first_build_warning() {  # the loud warning of --allow-first-build, at the start and at its step
    {
        printf '\n    %s\n' '*************************************************************************************'
        printf '    %s\n' 'WARNING: --allow-first-build. This build is NOT compared with the build that'
        printf '    %s\n' "$UPDATE_ANSWER_URL serves now. If it isn't above that build, installed"
        printf '    %s\n' 'copies may not take it as newer, or may go back to an older build. Use it only when'
        printf '    %s\n' 'the site serves no release at all.'
        printf '    %s\n\n' '*************************************************************************************'
    } >&2
}

# --- The Developer ID ---------------------------------------------------------------------------
# The same as install.sh's (install-signing-tests.sh tests both). A renewed certificate has the same
# name as the old one, and both are valid for a while, so the name alone is ambiguous to codesign.
# The one that expires last is chosen, by its SHA-1. The designated requirement names the team, not
# the certificate, so it is the same with either.

newest_developer_id() {  # newest_developer_id <find-identity -v output> <security find-certificate
    # -a -Z -p -c output>: the SHA-1 of the valid Developer ID that expires last, or nothing
    local hash expiry newest="" newest_expiry=0
    while IFS= read -r hash; do
        if [[ -z "$hash" ]]; then continue; fi
        expiry="$(certificate_expiry "$(certificate_of "$hash" "$2")")"
        if [[ -z "$newest" ]] || (( ${expiry:-0} > newest_expiry )); then
            newest="$hash"
            newest_expiry="${expiry:-0}"
        fi
    done <<< "$(developer_id_hashes "$1")"
    if [[ -n "$newest" ]]; then printf '%s\n' "$newest"; fi
}

developer_id_hashes() {  # developer_id_hashes <find-identity -v output>: the SHA-1 of each valid
    # Developer ID, in the order listed, once each (one in two keychains is listed twice)
    local line hash seen=" "
    while IFS= read -r line; do
        if [[ "$line" != *"\"$IDENTITY\""* ]]; then continue; fi
        line="${line#*) }"
        hash="${line%% *}"
        if [[ "$seen" == *" $hash "* ]]; then continue; fi
        seen="$seen$hash "
        printf '%s\n' "$hash"
    done <<< "$1"
}

certificate_of() {  # certificate_of <SHA-1> <security find-certificate -a -Z -p output>: its PEM, or nothing
    local line hash="" inside=false
    while IFS= read -r line; do
        if [[ "$line" == "SHA-1 hash: "* ]]; then hash="${line#SHA-1 hash: }"; fi
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" && "$hash" == "$1" ]]; then inside=true; fi
        if $inside; then printf '%s\n' "$line"; fi
        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then inside=false; fi
    done <<< "$2"
}

certificate_expiry() {  # certificate_expiry <PEM>: when it expires, in seconds since 1970, or nothing
    # openssl writes the month in English, so it is read in the C locale, by macOS's own date.
    local end
    end="$(openssl x509 -noout -enddate 2> /dev/null <<< "$1")" || return 0
    LC_ALL=C /bin/date -j -u -f '%b %e %T %Y %Z' "${end#notAfter=}" +%s 2> /dev/null || true
}

certificate_line() {  # certificate_line <SHA-1> <find-certificate output>: "SHA-1 …, valid until 17 Nov
    # 2031", or "SHA-1 …; its expiry could not be read"
    local expiry day
    expiry="$(certificate_expiry "$(certificate_of "$1" "$2")")"
    if [[ -z "$expiry" ]]; then
        printf 'SHA-1 %s; its expiry could not be read\n' "$1"
        return 0
    fi
    day="$(LC_ALL=C /bin/date -j -u -r "$expiry" '+%d %b %Y')"
    printf 'SHA-1 %s, valid until %s\n' "$1" "${day#0}"
}

describe_choice() {  # describe_choice <find-identity -v output> <find-certificate output> <chosen SHA-1>:
    # says which certificate it signs with and when that expires, and whether the choice is certain
    local hash count=0 unread=0
    while IFS= read -r hash; do
        if [[ -z "$hash" ]]; then continue; fi
        count=$(( count + 1 ))
        if [[ -z "$(certificate_expiry "$(certificate_of "$hash" "$2")")" ]]; then unread=$(( unread + 1 )); fi
    done <<< "$(developer_id_hashes "$1")"
    if (( count > 1 )); then
        info "$count valid certificates have that name (a renewal): it signs with the one that expires last."
        if (( unread == count )); then
            warn "none of their expiry dates could be read, so it signs with the first one listed, which may not be the one that expires last."
        elif (( unread > 0 )); then
            warn "the expiry date of $unread of them could not be read, so the one chosen may not be the one that expires last."
        fi
    fi
    info "Its certificate: $(certificate_line "$3" "$2")"
}

# --- The settings from the environment ----------------------------------------------------------
# release-settings-tests.sh tests these.

release_repo() {  # release_repo <TACTILE_RELEASE_REPO, or nothing>: the repository, owner/name; the
    # default when given nothing. Fails, printing nothing, for anything that isn't owner/name as
    # GitHub spells them.
    local repo="${1:-$DEFAULT_RELEASE_REPO}"
    [[ "$repo" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?/([A-Za-z0-9._-]{1,100})$ ]] || return 1
    [[ "${BASH_REMATCH[2]}" != "." && "${BASH_REMATCH[2]}" != ".." ]] || return 1
    printf '%s\n' "$repo"
}

build_number() {  # build_number <commit count> <TACTILE_BUILD_OFFSET, or nothing>: their sum, the
    # offset DEFAULT_BUILD_OFFSET when given nothing. Fails, printing nothing, unless both are whole
    # numbers written plainly (no sign, no leading zero), the offset at most 9 digits.
    local count="$1" offset="${2:-$DEFAULT_BUILD_OFFSET}"
    [[ "$count" =~ ^(0|[1-9][0-9]{0,8})$ && "$offset" =~ ^(0|[1-9][0-9]{0,8})$ ]] || return 1
    printf '%s\n' "$(( count + offset ))"
}

newest_mac_tag() {  # newest_mac_tag <tags, one per line>: the mac-v<major>.<minor>.<patch> tag with
    # the highest version, by number; nothing when there is none. Other tags are left out.
    local tag newest="" newest_key="" key
    while IFS= read -r tag; do
        [[ "$tag" =~ ^mac-v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$ ]] || continue
        key="$(printf '%09d%09d%09d' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")"
        if [[ -z "$newest" || "$key" > "$newest_key" ]]; then
            newest="$tag"
            newest_key="$key"
        fi
    done <<< "$1"
    if [[ -n "$newest" ]]; then printf '%s\n' "$newest"; fi
}

build_is_newer() {  # build_is_newer <build> <published build>: succeeds when the first is greater;
    # fails when it isn't, or when either isn't a plain whole number
    [[ "$1" =~ ^(0|[1-9][0-9]{0,9})$ && "$2" =~ ^(0|[1-9][0-9]{0,9})$ ]] || return 1
    (( $1 > $2 ))
}

above_served_build() {  # above_served_build <build> <the site's answer from /api/mac/update>: prints
    # the build the answer holds. Succeeds when <build> is greater; fails with 1 when it isn't, and
    # with 2, printing nothing, when the answer holds no build (not JSON, an error, or a build that
    # isn't a whole number)
    local served
    served="$(plutil -extract build raw -expect integer -o - - <<< "$2" 2> /dev/null)" || return 2
    [[ "$served" =~ ^(0|[1-9][0-9]{0,9})$ ]] || return 2
    printf '%s\n' "$served"
    build_is_newer "$1" "$served" || return 1
}

# Sourced (by install-signing-tests.sh and release-settings-tests.sh), it stops here, having only
# defined what is above.
(return 0 2> /dev/null) && return 0

# --- Arguments ----------------------------------------------------------------------------------

dry_run=false
allow_first_build=false
notes_file=""
key_id="k1"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        --allow-first-build) allow_first_build=true ;;
        --notes|--key-id)
            if [[ $# -lt 2 || -z "$2" ]]; then
                printf 'release.sh: %s needs a value\n\n' "$1" >&2; usage >&2; exit 1
            fi
            if [[ "$1" == "--notes" ]]; then notes_file="$2"; else key_id="$2"; fi
            shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'release.sh: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done
if [[ ! "$key_id" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; then
    printf "release.sh: '%s' is not a keyId (letters, digits, '.', '_' and '-'; the first key is k1)\n" "$key_id" >&2
    exit 1
fi
if [[ -n "$notes_file" ]]; then   # made absolute now: the run changes folder
    [[ -f "$notes_file" && -r "$notes_file" ]] || { printf 'release.sh: no readable notes file at %s\n' "$notes_file" >&2; exit 1; }
    notes_file="$(cd -P "$(dirname "$notes_file")" && pwd)/$(basename "$notes_file")"
    if ! grep -q '[^[:space:]]' "$notes_file"; then
        printf 'release.sh: the notes file %s is empty\n' "$notes_file" >&2; exit 1
    fi
elif ! $dry_run; then
    printf 'release.sh: --notes <file> is required for a release (plain text, one paragraph per line)\n\n' >&2
    usage >&2
    exit 1
fi
GITHUB_REPO="$(release_repo "${TACTILE_RELEASE_REPO:-}")" || {
    printf "release.sh: TACTILE_RELEASE_REPO is '%s', not a GitHub repository written owner/name\n" \
        "${TACTILE_RELEASE_REPO:-}" >&2
    exit 1
}
readonly GITHUB_REPO
if ! build_number 0 "${TACTILE_BUILD_OFFSET:-}" > /dev/null; then
    printf "release.sh: TACTILE_BUILD_OFFSET is '%s', not a whole number (0 to 999999999)\n" \
        "${TACTILE_BUILD_OFFSET:-}" >&2
    exit 1
fi
readonly BUILD_OFFSET="${TACTILE_BUILD_OFFSET:-$DEFAULT_BUILD_OFFSET}"

# The Mac app's folder (the repository's root) is the folder above this script's own (through any
# symbolic links to it).
script="${BASH_SOURCE[0]}"
while [[ -L "$script" ]]; do
    link_dir="$(cd -P "$(dirname "$script")" && pwd)"
    script="$(readlink "$script")"
    [[ "$script" == /* ]] || script="$link_dir/$script"
done
mac_dir="$(cd -P "$(dirname "$script")/.." && pwd)"
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"

# --- State, and tidying up on the way out -------------------------------------------------------

work=""           # the run's folder in $TMPDIR (kept, and named at the end)
logs=""
lock_held=false
child=""          # a codesign started by run_limited, which must not outlive the run
mounted=""        # the disk image's mount point while it is attached
publishing=false  # gh release create has started and its result is not yet confirmed
finished=false
tag=""
assets=()

say() {  # a message on the way out: a closed terminal or a broken pipe must not stop the tidying
    printf '%s\n' "$*" >&2 2> /dev/null || true
}

on_exit() {
    local status=$?
    trap '' INT TERM HUP QUIT PIPE
    set +e
    if [[ -n "$child" ]]; then kill -TERM "$child" 2> /dev/null; wait "$child" 2> /dev/null; fi
    if [[ -n "$mounted" ]]; then
        hdiutil detach -quiet "$mounted" > /dev/null 2>&1 || hdiutil detach -quiet -force "$mounted" > /dev/null 2>&1
    fi
    if [[ -n "$work" && -d "$work" ]]; then   # the big, rebuildable parts; the results and logs stay
        rm -rf "$work/src" "$work/DerivedData" "$work/tool-build" "$work/tmp" "$work/check" "$work/dmg-root" \
            "$work/dmg-mount" 2> /dev/null
        # A run that stopped before making anything leaves nothing behind (rmdir removes only empty folders).
        rmdir "$work/release" "$work/logs" 2> /dev/null
        if rmdir "$work" 2> /dev/null; then work=""; fi
    fi
    local code=$status
    if ! $finished; then
        local why=""
        case "$status" in
            0) ;;
            129) why="Stopped: the terminal was closed." ;;
            130) why="Interrupted (Ctrl-C)." ;;
            131) why="Interrupted (Ctrl-\\)." ;;
            141) why="Stopped: its output was cut off (a broken pipe)." ;;
            143) why="Stopped (SIGTERM)." ;;
            *) $explained || why="Stopped by an unexpected error (status $status)." ;;
        esac
        if [[ -n "$why" ]]; then say ""; say "release.sh: $why"; fi
        if $publishing; then
            code=2
            say "    Publishing had started, so release $tag may exist on GitHub with files missing."
            say "    The website serves only a release that has all four files, so nothing broken is offered."
            say "    To see it:     gh release view $tag --repo $GITHUB_REPO"
            local files="<the four files>"
            if [[ ${#assets[@]} -gt 0 ]]; then files="${assets[*]}"; fi
            say "    To finish it:  gh release upload $tag --repo $GITHUB_REPO --clobber \\"
            say "                     $files"
            say "    Or delete it (the tag stays) and run this again:"
            say "                   gh release delete $tag --repo $GITHUB_REPO --yes"
        elif [[ $status -ne 0 ]]; then
            code=1
            say "    Nothing was published."
        fi
        if [[ -n "$work" && -d "$work" ]]; then say "    This run's folder (its logs, and what it made): $work"; fi
    fi
    if $lock_held; then
        read_lock_holder
        if [[ "$lock_pid" == "$$" ]]; then rm -f "$LOCK_PATH"; fi
    fi
    exit "$code"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 129' HUP
trap 'exit 143' TERM
trap 'exit 141' PIPE

# --- Small helpers ------------------------------------------------------------------------------

plist_value() {  # plist_value <plist> <key>: the value, or nothing (also when there is no such file)
    [[ -f "$1" ]] || return 0
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2> /dev/null || true
}

cdhash() {  # cdhash <code>: the code directory hash of its signature, or nothing
    codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1
}

size_of() { stat -f %z "$1"; }
human_size() {  # human_size <bytes>: "3.2 MB", "1.1 KB", "180 bytes"
    awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b / 1048576; else if (b >= 1024) printf "%.1f KB", b / 1024; else printf "%d bytes", b }'
}

run_limited() {  # run_limited <seconds> <command...>: its status, or 124 when it was stopped at the limit
    local limit="$1" ticks=0 status=0
    shift
    "$@" &
    child=$!
    while kill -0 "$child" 2> /dev/null; do
        if (( ticks >= limit * 2 )); then
            kill -TERM "$child" 2> /dev/null || true
            wait "$child" 2> /dev/null || true
            child=""
            return 124
        fi
        sleep 0.5
        ticks=$(( ticks + 1 ))
    done
    wait "$child" || status=$?
    child=""
    return "$status"
}

sign_with_developer_id() {  # sign_with_developer_id <file> <log>: codesign with a secure timestamp, time-limited
    local file="$1" log="$2" status=0
    run_limited "$SIGNING_WAIT_SECONDS" codesign --force --sign "$signing_identity" --timestamp "$file" > "$log" 2>&1 || status=$?
    if [[ $status -eq 124 ]]; then
        fail "codesign was still waiting after $SIGNING_WAIT_SECONDS seconds to sign with the Developer ID key, so it was stopped." \
            "macOS is probably showing a Keychain prompt for that key on this Mac's screen." \
            "Answer it with Always Allow (it asks for the login password), then run this again."
    elif [[ $status -ne 0 ]]; then
        local said
        said="$(tail -n 5 "$log")"
        if grep -qi 'timestamp' "$log"; then
            fail "codesign could not get a secure timestamp from Apple's server (status $status). Is this Mac online?" \
                "Notarization needs the timestamp, so a release can't be made without it." "codesign said: $said"
        fi
        fail "codesign could not sign $file with $IDENTITY (status $status)." "codesign said: $said"
    fi
}

json_value() {  # json_value <file> <key path>: a value from a JSON file, as plain text
    plutil -extract "$2" raw -o - "$1" 2> /dev/null
}

notarize() {  # notarize <file> <what> <name>: submits, waits, and stops unless Apple accepts it
    local file="$1" what="$2" name="$3" result status id
    result="$logs/notarize-$name.json"
    info "Submitting $what to Apple's notary service, and waiting (usually a few minutes)..."
    if ! xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
            > "$result" 2> "$logs/notarize-$name.err"; then
        fail "notarytool could not submit $what, or stopped waiting for it." \
            "What it said: $logs/notarize-$name.err and $result"
    fi
    status="$(json_value "$result" status)" || status=""
    id="$(json_value "$result" id)" || id=""
    if [[ "$status" != "Accepted" ]]; then
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$logs/notarize-$name-log.json" > /dev/null 2>&1 || true
        fi
        fail "Apple did not accept $what (status: ${status:-unknown}, submission ${id:-unknown})." \
            "Apple's log of it: $logs/notarize-$name-log.json (or: xcrun notarytool log ${id:-<id>} --keychain-profile $NOTARY_PROFILE)"
    fi
    info "Accepted (submission $id)."
}

staple() {  # staple <file> <what>: attaches the notarization ticket and checks it
    local file="$1" what="$2"
    xcrun stapler staple "$file" > "$logs/staple-${file##*/}.log" 2>&1 || \
        fail "Could not staple the notarization ticket to $what." "The log: $logs/staple-${file##*/}.log"
    xcrun stapler validate "$file" > /dev/null 2>&1 || fail "The ticket stapled to $what does not validate."
    info "Ticket stapled to $what, and it validates."
}

check_app() {  # check_app <app> <what>: the checks the updater makes (the contract's step 4 and 5)
    local app="$1" what="$2" out plist
    plist="$app/Contents/Info.plist"
    out="$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1)" || \
        fail "The signature of $what does not verify (codesign --verify --deep --strict)." "$out"
    out="$(codesign --verify --deep --strict -R "=$APP_REQUIREMENT" "$app" 2>&1)" || \
        fail "$what does not satisfy the code requirement the updater checks:" "$APP_REQUIREMENT" "$out"
    [[ "$(plist_value "$plist" CFBundleIdentifier)" == "$BUNDLE_ID" ]] || fail "$what is not $BUNDLE_ID."
    [[ "$(plist_value "$plist" CFBundleShortVersionString)" == "$version" ]] || \
        fail "$what's version is '$(plist_value "$plist" CFBundleShortVersionString)', not $version."
    [[ "$(plist_value "$plist" CFBundleVersion)" == "$build" ]] || \
        fail "$what's build is '$(plist_value "$plist" CFBundleVersion)', not $build."
}

read_lock_holder() {  # sets lock_pid to the process ID in the lock, or nothing (no subshell: see on_exit)
    lock_pid=""
    IFS= read -r lock_pid 2> /dev/null < "$LOCK_PATH" || true
    lock_pid="${lock_pid//[!0-9]/}"
}

take_lock() {  # as install.sh's: shlock makes the lock in one step; a stale one (its run has gone) is
               # taken over by renaming it to a name of this run's own, which only one run can do.
    if /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null; then return 0; fi
    local holder renamed="" mine="$LOCK_PATH.stale-$$"
    read_lock_holder; holder="$lock_pid"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2> /dev/null; then return 1; fi
    rm -f "$mine"
    if ! mv "$LOCK_PATH" "$mine" 2> /dev/null; then
        /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null
        return
    fi
    IFS= read -r renamed 2> /dev/null < "$mine" || true
    renamed="${renamed//[!0-9]/}"
    if [[ -n "$renamed" && "$renamed" != "$holder" ]] && kill -0 "$renamed" 2> /dev/null; then
        ln "$mine" "$LOCK_PATH" 2> /dev/null || true
        rm -f "$mine"
        return 1
    fi
    rm -f "$mine"
    /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null
}

# --- Before building ----------------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "Tactile is released only from a Mac."
[[ "$(id -u)" -ne 0 ]] || fail "Run this as yourself, not with sudo or as root: the keys are in your login keychain."
for needed in git xcodebuild xcrun codesign ditto hdiutil shasum swift security plutil lipo stat awk curl \
        /usr/bin/shlock /usr/libexec/PlistBuddy; do
    command -v "$needed" > /dev/null || fail "$needed was not found. Install Xcode (and open it once) first."
done
if ! $dry_run; then
    command -v gh > /dev/null || fail "gh (GitHub's command-line tool) was not found. Install it (brew install gh) and run gh auth login."
fi
root="$(git -C "$mac_dir" rev-parse --show-toplevel 2> /dev/null)" || fail "$mac_dir is not in a git checkout."
mac_rel="$(git -C "$mac_dir" rev-parse --show-prefix)"   # empty at the repository's root
mac_rel="${mac_rel%/}"
[[ -d "$mac_dir/Tactile.xcodeproj" ]] || fail "No Tactile.xcodeproj in $mac_dir."

if $dry_run; then
    printf 'Tactile release: DRY RUN. Nothing will be notarized or published.\n'
else
    printf 'Tactile release\n'
fi
if $allow_first_build; then first_build_warning; fi

mkdir -p "$(dirname "$LOCK_PATH")"
if ! take_lock; then
    read_lock_holder
    fail "Another run of release.sh is going on (pid ${lock_pid:-unknown}). Wait for it to finish." \
        "Its lock is $LOCK_PATH."
fi
lock_held=true

work="$(mktemp -d "$tmp_root/tactile-release.XXXXXX")"
work="$(cd -P "$work" && pwd)"
case "$work/" in
    "$root/"*) fail "The scratch folder $work is inside the repository. Set TMPDIR elsewhere." ;;
esac
logs="$work/logs"
out="$work/release"
mkdir -p "$logs" "$out" "$work/tmp"

step "Checking the checkout"
[[ "$(git -C "$root" rev-parse --is-shallow-repository)" == "false" ]] || \
    fail "This checkout is shallow, so the build number (from git rev-list --count HEAD) would be wrong." \
        "Fetch the whole history (git fetch --unshallow), then run this again."
changes="$(git -C "$root" status --porcelain --untracked-files=all)"
if [[ -n "$changes" ]]; then
    count="$(wc -l <<< "$changes" | tr -d ' ')"
    shown=()
    while IFS= read -r line; do shown+=("  $line"); done < <(head -n 5 <<< "$changes")
    fail "The working tree is not clean ($count changed or untracked files): a release is built only from a committed, tagged tree." \
        "Commit or stash them, then run this again. The first of them:" "${shown[@]}"
fi
commit="$(git -C "$root" rev-parse HEAD)"
short="$(git -C "$root" rev-parse --short HEAD)"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
info "$root: branch $branch, at $short. The working tree is clean."

pbxproj="$(git -C "$root" show "$commit:${mac_rel:+$mac_rel/}Tactile.xcodeproj/project.pbxproj")" || \
    fail "Could not read the project at $short."
versions="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = "\{0,1\}\([^";]*\)"\{0,1\};[[:space:]]*$/\1/p' <<< "$pbxproj" | sort -u)"
if [[ -z "$versions" ]]; then
    fail "The project has no MARKETING_VERSION, so there is no version to release."
elif [[ "$(wc -l <<< "$versions" | tr -d ' ')" != "1" ]]; then
    fail "The project's configurations have different MARKETING_VERSIONs ($(tr '\n' ' ' <<< "$versions")): make them one."
fi
version="$versions"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    fail "The project's MARKETING_VERSION is '$version'; a release needs <major>.<minor>.<patch>."
tag="mac-v$version"
commits="$(git -C "$root" rev-list --count "$commit")"
build="$(build_number "$commits" "$BUILD_OFFSET")" || fail "Could not make a build number from $commits commits and the offset $BUILD_OFFSET."
if [[ "$BUILD_OFFSET" == "0" ]]; then
    info "Version $version (MARKETING_VERSION), build $build (git rev-list --count HEAD)."
else
    info "Version $version (MARKETING_VERSION), build $build (git rev-list --count HEAD, $commits, plus TACTILE_BUILD_OFFSET, $BUILD_OFFSET)."
fi

# The tag. What is built is $commit itself (HEAD when the run began, clean), exported below with git
# archive in this same run; so when the tag points at $commit, the released app is the tagged commit
# by construction, whatever happens to the checkout meanwhile: never publish a build of another
# commit under a tag.
tags_here="$(git -C "$root" tag --points-at "$commit")"
tag_commit="$(git -C "$root" rev-parse -q --verify "refs/tags/$tag^{commit}" 2> /dev/null)" || tag_commit=""
if grep -qx -- "$tag" <<< "$tags_here"; then
    info "HEAD is tagged $tag."
elif [[ -n "$tag_commit" ]]; then
    not_required "The tag $tag is on another commit (${tag_commit:0:7}), not on HEAD ($short)." \
        "Check out $tag to release it, or bump MARKETING_VERSION for a new release."
else
    others="$(grep '^mac-v' <<< "$tags_here" | tr '\n' ' ' || true)"
    if [[ -n "$others" ]]; then
        not_required "HEAD is tagged ${others% }, not $tag: the tag and the project's version ($version) must agree."
    else
        not_required "HEAD ($short) is not tagged $tag." \
            "Tag it and push the tag: git tag -a $tag -m 'Tactile $version' && git push origin $tag"
    fi
fi

step "Checking the Developer ID identity"
identities="$(security find-identity -v -p codesigning 2> /dev/null)" || identities=""
if grep -qF "\"$IDENTITY\"" <<< "$identities"; then
    info "In the keychain: $IDENTITY"
    certificates="$(security find-certificate -a -Z -p -c "$IDENTITY" 2> /dev/null)" || certificates=""
    signing_identity="$(newest_developer_id "$identities" "$certificates")"
    describe_choice "$identities" "$certificates" "$signing_identity"
else
    fail "The signing identity '$IDENTITY' is not in the keychain (security find-identity -v -p codesigning)." \
        "Releases are signed with it. It lives in this Mac's login keychain; restore it there (Xcode > Settings > Accounts)."
fi

step "Checking notarization and GitHub"
if $dry_run; then
    info "Skipped in a dry run: the notarytool profile $NOTARY_PROFILE, gh's sign-in and access to $GITHUB_REPO,"
    info "that there is no release $tag yet, that GitHub has the tag at this commit, and that build"
    info "$build is above the newest release's."
else
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2> "$logs/notary-check.log"; then
        fail "The notarytool profile $NOTARY_PROFILE is missing, or Apple did not accept it." \
            "Make it once, in your own terminal (it asks for an app-specific password from appleid.apple.com):" \
            "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID" \
            "What notarytool said: $logs/notary-check.log"
    fi
    info "The notarytool profile $NOTARY_PROFILE works."
    gh auth status --hostname github.com > /dev/null 2>&1 || \
        fail "gh is not signed in to GitHub. Run gh auth login, then run this again."
    gh repo view "$GITHUB_REPO" --json nameWithOwner > /dev/null 2>&1 || \
        fail "gh can't read $GITHUB_REPO with the account it is signed in with (gh auth status says which)."
    info "gh is signed in and can read $GITHUB_REPO."
    if gh release view "$tag" --repo "$GITHUB_REPO" > /dev/null 2> "$logs/release-check.log"; then
        fail "There is already a release $tag on GitHub. A version is released once: bump MARKETING_VERSION for a new one."
    elif ! grep -qi 'not found' "$logs/release-check.log"; then
        fail "Could not check whether release $tag exists on GitHub." "gh said: $(head -n 3 "$logs/release-check.log")"
    fi
    info "There is no release $tag yet."
    remote_commit="$(gh api "repos/$GITHUB_REPO/commits/$tag" --jq .sha 2> /dev/null)" || remote_commit=""
    if [[ "$remote_commit" != "$commit" ]]; then
        fail "GitHub does not have the tag $tag at this commit (${remote_commit:-no such tag there}; HEAD is $commit)." \
            "Push it: git push origin $tag"
    fi
    info "GitHub has the tag $tag at this commit."
    # Builds only ever grow: the build must be above the newest release's, as its update.json says.
    releases="$(gh release list --repo "$GITHUB_REPO" --exclude-drafts --limit 1000 --json tagName \
        --jq '.[].tagName' 2> "$logs/release-list.err")" || \
        fail "Could not list the releases of $GITHUB_REPO." "gh said: $(head -n 3 "$logs/release-list.err")"
    newest="$(newest_mac_tag "$releases")"
    if [[ -z "$releases" ]]; then
        info "$GITHUB_REPO has no release yet: build $build is its first."
    elif [[ -z "$newest" ]]; then
        fail "$GITHUB_REPO has releases, but none tagged mac-v<version>, so the newest Tactile build can't be read."
    else
        mkdir -p "$work/tmp/newest"
        gh release download "$newest" --repo "$GITHUB_REPO" --pattern update.json --dir "$work/tmp/newest" \
            > /dev/null 2> "$logs/newest-manifest.err" || \
            fail "Could not download update.json of $newest, the newest release in $GITHUB_REPO." \
                "gh said: $(head -n 3 "$logs/newest-manifest.err")"
        published_build="$(json_value "$work/tmp/newest/update.json" build)" || published_build=""
        [[ "$published_build" =~ ^(0|[1-9][0-9]{0,9})$ ]] || \
            fail "Could not read the build in update.json of $newest ('${published_build}')."
        build_is_newer "$build" "$published_build" || \
            fail "Build $build is not above build $published_build of $newest, the newest release in $GITHUB_REPO." \
                "Builds must only grow. Set TACTILE_BUILD_OFFSET so this one is above it (RELEASING.md," \
                "\"Where releases go, and the build number\"), or check that this is the repository you meant."
        info "Build $build is above build $published_build of $newest, the newest release."
    fi
fi

# The site's answer names the newest build installed copies know of, wherever it was released from:
# a repository's first release has none of its own to compare with, but the site's is still there.
step "Checking build $build against the build $UPDATE_SITE serves now"
if $allow_first_build; then
    first_build_warning
else
    served_answer="$(curl --silent --show-error --fail --proto '=https' --max-time 30 "$UPDATE_ANSWER_URL" \
        2> "$logs/served-build.err")" || served_answer=""
    verdict=0
    served_build="$(above_served_build "$build" "$served_answer")" || verdict=$?
    case "$verdict" in
        0) info "Build $build is above build $served_build, which $UPDATE_ANSWER_URL serves now." ;;
        1) not_required "Build $build is not above build $served_build, which $UPDATE_ANSWER_URL serves now." \
               "Installed copies would not take it as newer. Builds must only grow: set TACTILE_BUILD_OFFSET so" \
               "this one is above it (RELEASING.md, \"Where releases go, and the build number\")." ;;
        *) if [[ -n "$served_answer" ]]; then
               served_why="The site answered, but its answer holds no build."
           else
               served_why="curl said: $(head -n 3 "$logs/served-build.err" 2> /dev/null)"
           fi
           not_required "Could not read the build $UPDATE_ANSWER_URL serves now, so build $build can't be compared with it." \
               "$served_why" \
               "Is this Mac online? If the site serves no release at all (it answers 404), run this again" \
               "with --allow-first-build." ;;
    esac
fi

# --- The update key's tool, and the keys --------------------------------------------------------

# Exporting the commit, not building the checkout: what is built is exactly $commit, the tagged
# commit, and nothing uncommitted, untracked or ignored can get in, even if the checkout changes during
# the build.
step "Exporting the commit to build"
mkdir -p "$work/src"
git -C "$root" archive --format=tar "$commit" -- "${mac_rel:-.}" | tar -x -C "$work/src" || \
    fail "Could not export $short with git archive."
src="$work/src/${mac_rel:-.}"
info "$short exported to $src (git archive: only what is committed)."

step "Building tactile-release, the update key's tool"
tool_package="$src/Tools/tactile-release"
if ! TMPDIR="$work/tmp/" swift build -c release --package-path "$tool_package" --scratch-path "$work/tool-build" \
        > "$logs/tool-build.log" 2>&1; then
    fail "Building tactile-release failed." "The log: $logs/tool-build.log"
fi
tool="$(TMPDIR="$work/tmp/" swift build -c release --package-path "$tool_package" --scratch-path "$work/tool-build" \
    --show-bin-path 2> /dev/null)/tactile-release"
[[ -x "$tool" ]] || fail "The build said it succeeded, but there is no tactile-release at $tool."
info "Built."

step "Checking update key $key_id"
public_key="$("$tool" public-key --key-id "$key_id" 2> "$logs/public-key.err")" || \
    fail "Could not read update key $key_id from the keychain." "$(cat "$logs/public-key.err")" \
        "Tools/RELEASING.md has the commands."
info "In the login keychain. Its public key: $public_key"

step "Checking that the Developer ID key can sign"
info "Signing a scratch file with it, with a secure timestamp from Apple's server. If macOS asks"
info "whether codesign may use the key, choose Always Allow: a release signs several times."
cp /usr/bin/true "$work/tmp/signing-check"
sign_with_developer_id "$work/tmp/signing-check" "$logs/signing-check.log"
info "It can, with a secure timestamp."

# --- Building -----------------------------------------------------------------------------------

step "Building Tactile $version (build $build): Release, signed with the Developer ID"
archive="$work/Tactile.xcarchive"
info "xcodebuild archive, in $work; this takes a few minutes."
# The signing settings are given here, for this build only: Manual signing with the Developer ID
# (the certificate chosen above, by its SHA-1), a secure timestamp, the build number. The project
# itself signs ad hoc (Config/Signing.xcconfig), and the export has no Signing.local.xcconfig
# (it is git-ignored), so a release never depends on either. ENABLE_HARDENED_RUNTIME is already YES in
# the project.
# No -allowProvisioningUpdates: nothing is asked of Apple's servers but the timestamp.
if ! TMPDIR="$work/tmp/" xcodebuild archive \
        -project "$src/Tactile.xcodeproj" -scheme Tactile -configuration Release \
        -destination 'generic/platform=macOS' -archivePath "$archive" -derivedDataPath "$work/DerivedData" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$signing_identity" DEVELOPMENT_TEAM="$TEAM_ID" \
        PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp \
        CURRENT_PROJECT_VERSION="$build" > "$logs/xcodebuild-archive.log" 2>&1; then
    errors="$(grep -E 'error:|ARCHIVE FAILED' "$logs/xcodebuild-archive.log" | head -n 20 || true)"
    if [[ -n "$errors" ]]; then printf '\n%s\n' "$errors" >&2; else printf '\n' >&2; tail -n 30 "$logs/xcodebuild-archive.log" >&2; fi
    fail "The Release build failed." "The whole log: $logs/xcodebuild-archive.log"
fi
built="$archive/Products/Applications/Tactile.app"
[[ -d "$built" ]] || fail "The archive was made, but there is no app at $built."
mkdir -p "$work/app"
app="$work/app/Tactile.app"
ditto "$built" "$app"
info "Built: $app"

step "Checking the app"
check_app "$app" "The built app"
plist="$app/Contents/Info.plist"
min_os="$(plist_value "$plist" LSMinimumSystemVersion)"
[[ -n "$min_os" ]] || fail "The built app has no LSMinimumSystemVersion."
info "Tactile $version (build $build), $BUNDLE_ID, for macOS $min_os or later; $(lipo -archs "$app/Contents/MacOS/Tactile" 2> /dev/null || echo 'architectures unknown')"
info "Signature: valid (codesign --verify --deep --strict)"
info "The code requirement the updater checks: satisfied (Developer ID, team $TEAM_ID, $BUNDLE_ID)"
sign_info="$(codesign -dvv "$app" 2>&1)"
authority="$(sed -n 's/^Authority=//p' <<< "$sign_info" | head -n 1)"
[[ "$authority" == "$IDENTITY" ]] || fail "The app is signed by '${authority:-nobody}', not $IDENTITY."
[[ "$(sed -n 's/^TeamIdentifier=//p' <<< "$sign_info")" == "$TEAM_ID" ]] || fail "The app's team is not $TEAM_ID."
info "Signed by: $authority"
timestamp="$(sed -n 's/^Timestamp=//p' <<< "$sign_info")"
[[ -n "$timestamp" ]] || fail "The app's signature has no secure timestamp, which notarization requires." \
    "(codesign shows a 'Signed Time', not a 'Timestamp'.) Check OTHER_CODE_SIGN_FLAGS=--timestamp in this script."
info "Secure timestamp: $timestamp"
flags="$(sed -n 's/^CodeDirectory .*flags=\(0x[0-9a-f]*([^)]*)\).*/\1/p' <<< "$sign_info")"
[[ "$flags" == *runtime* ]] || fail "The app does not have the hardened runtime (its flags: ${flags:-none})." \
    "ENABLE_HARDENED_RUNTIME must stay YES in Tactile.xcodeproj."
info "Hardened runtime: yes ($flags)"
entitlements="$work/tmp/entitlements.plist"
codesign -d --entitlements - --xml "$app" > "$entitlements" 2> /dev/null || fail "Could not read the app's entitlements."
if [[ -s "$entitlements" ]]; then
    plutil -lint -s "$entitlements" > /dev/null 2>&1 || fail "The app's entitlements are not a valid property list."
    [[ "$(plist_value "$entitlements" com.apple.security.get-task-allow)" != "true" ]] || \
        fail "The app has the get-task-allow entitlement (a debug build's), which notarization refuses."
    [[ "$(plist_value "$entitlements" com.apple.security.app-sandbox)" != "true" ]] || \
        fail "The app is sandboxed, and Tactile can't read touchscreens or post events in the sandbox."
fi
info "Entitlements: no get-task-allow, no sandbox"
app_hash="$(cdhash "$app")"
[[ -n "$app_hash" ]] || fail "Could not read the app's code directory hash."

step "Checking the app's update settings: update key $key_id, and $UPDATE_SITE"
# The values the app trusts are in its Info.plist (TactileUpdateKeys, TactileUpdateBaseURL), read here
# by the app's own code. An Info.plist that doesn't trust the key would ship a Tactile that refuses the
# next update; one the app can't read would ship a Tactile with updates off.
if found="$("$tool" check-settings --key-id "$key_id" --public-key "$public_key" --site "$UPDATE_SITE" "$app" \
        2> "$logs/check-settings.err")"; then
    info "$found"
else
    not_required "The app's update settings won't do for a release signed with $key_id." \
        "$(cat "$logs/check-settings.err")" \
        "Fix TACTILE_UPDATE_KEYS or TACTILE_UPDATE_BASE_URL in Config/Updates.xcconfig; then commit, tag, and run this again."
fi

# --- Notarizing and packing ---------------------------------------------------------------------

step "Notarizing the app"
if $dry_run; then
    would "zip the app, submit it with xcrun notarytool submit --keychain-profile $NOTARY_PROFILE --wait,"
    would "staple the ticket to it (xcrun stapler staple), and check it with stapler validate and spctl"
else
    mkdir -p "$work/tmp/notarize"
    ditto -c -k --keepParent "$app" "$work/tmp/notarize/Tactile.zip"
    notarize "$work/tmp/notarize/Tactile.zip" "the app" app
    staple "$app" "the app"
    assessment="$(spctl --assess --type execute -vv "$app" 2>&1)" || \
        fail "Gatekeeper does not accept the notarized app (spctl --assess)." "$assessment"
    grep -q 'source=Notarized Developer ID' <<< "$assessment" || \
        fail "Gatekeeper accepts the app, but not as notarized Developer ID:" "$assessment"
    info "Gatekeeper accepts it: Notarized Developer ID."
    app_hash="$(cdhash "$app")"
fi

step "Packing the update: Tactile-$version.zip"
zip="$out/Tactile-$version.zip"
ditto -c -k --keepParent "$app" "$zip"
# What is inside, unpacked as the updater unpacks it: one Tactile.app, passing its checks.
mkdir -p "$work/check/zip"
ditto -x -k "$zip" "$work/check/zip"
inside="$(ls -A "$work/check/zip")"
[[ "$inside" == "Tactile.app" ]] || fail "The zip does not hold just Tactile.app; it holds: $(tr '\n' ' ' <<< "$inside")"
check_app "$work/check/zip/Tactile.app" "The app in the zip"
[[ "$(cdhash "$work/check/zip/Tactile.app")" == "$app_hash" ]] || fail "The app in the zip is not the app just checked."
if ! $dry_run; then
    xcrun stapler validate "$work/check/zip/Tactile.app" > /dev/null 2>&1 || fail "The app in the zip has no valid stapled ticket."
fi
info "$(human_size "$(size_of "$zip")"). Unpacked with ditto -x -k it holds just Tactile.app: signature valid, the"
info "updater's code requirement satisfied, $version (build $build), the same signature (CDHash $app_hash)."

step "Making the disk image: Tactile-$version.dmg"
dmg="$out/Tactile-$version.dmg"
mkdir -p "$work/dmg-root"
ditto "$app" "$work/dmg-root/Tactile.app"
ln -s /Applications "$work/dmg-root/Applications"
if ! hdiutil create -volname Tactile -srcfolder "$work/dmg-root" -fs HFS+ -format UDZO -imagekey zlib-level=9 \
        -ov "$dmg" > "$logs/hdiutil-create.log" 2>&1; then
    fail "hdiutil could not make the disk image." "The log: $logs/hdiutil-create.log"
fi
sign_with_developer_id "$dmg" "$logs/codesign-dmg.log"
out_text="$(codesign --verify --strict -R "=$DMG_REQUIREMENT" "$dmg" 2>&1)" || \
    fail "The disk image's signature does not verify, or is not Cristian's Developer ID." "$out_text"
hdiutil verify "$dmg" > "$logs/hdiutil-verify.log" 2>&1 || fail "hdiutil verify fails on the disk image." "The log: $logs/hdiutil-verify.log"
info "Made, signed with the Developer ID (secure timestamp), and its checksum verifies."

step "Notarizing the disk image"
if $dry_run; then
    would "submit it with xcrun notarytool submit --keychain-profile $NOTARY_PROFILE --wait,"
    would "staple the ticket to it (xcrun stapler staple), and check it with stapler validate and spctl"
else
    notarize "$dmg" "the disk image" dmg
    staple "$dmg" "the disk image"
    assessment="$(spctl --assess --type open --context context:primary-signature -vv "$dmg" 2>&1)" || \
        fail "Gatekeeper does not accept the notarized disk image (spctl --assess)." "$assessment"
    grep -q 'source=Notarized Developer ID' <<< "$assessment" || \
        fail "Gatekeeper accepts the disk image, but not as notarized Developer ID:" "$assessment"
    info "Gatekeeper accepts it: Notarized Developer ID."
fi

step "Checking what is in the disk image"
mkdir -p "$work/dmg-mount"
hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$work/dmg-mount" > "$logs/hdiutil-attach.log" 2>&1 || \
    fail "Could not attach the disk image to check it." "The log: $logs/hdiutil-attach.log"
mounted="$work/dmg-mount"
[[ -d "$mounted/Tactile.app" ]] || fail "The disk image has no Tactile.app."
[[ -L "$mounted/Applications" && "$(readlink "$mounted/Applications")" == "/Applications" ]] || \
    fail "The disk image has no Applications link."
[[ "$(cdhash "$mounted/Tactile.app")" == "$app_hash" ]] || fail "The app in the disk image is not the app just checked."
codesign --verify --deep --strict -R "=$APP_REQUIREMENT" "$mounted/Tactile.app" > /dev/null 2>&1 || \
    fail "The app in the disk image does not verify."
hdiutil detach -quiet "$mounted" > /dev/null 2>&1 || hdiutil detach -quiet -force "$mounted" > /dev/null 2>&1 || \
    warn "could not detach $mounted; it is detached when the Mac restarts (or: hdiutil detach $mounted)"
mounted=""
info "$(human_size "$(size_of "$dmg")"). It holds Tactile.app (the same signature, CDHash $app_hash) and an Applications link."

# --- The update's signature, update.json, SHA256SUMS --------------------------------------------

step "Signing the update with update key $key_id"
signature="$("$tool" sign --key-id "$key_id" "$zip" 2> "$logs/sign.err")" || \
    fail "Could not sign the zip with update key $key_id." "$(cat "$logs/sign.err")"
"$tool" verify --public-key "$public_key" --signature "$signature" "$zip" > /dev/null 2> "$logs/verify.err" || \
    fail "The update's signature does not verify with the public key of $key_id." "$(cat "$logs/verify.err")"
info "Signature: $signature"
info "It verifies over Tactile-$version.zip with the public key of $key_id."

step "Writing update.json and SHA256SUMS"
if [[ -z "$notes_file" ]]; then
    notes_file="$work/notes.txt"
    printf 'Dry run: no release notes were given.\n' > "$notes_file"
    info "No --notes in this dry run: update.json says so instead."
fi
# GitHub reads the notes as Markdown, where lines are joined into one paragraph: a blank line between.
awk 'NF { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if (n++) print ""; print }' "$notes_file" > "$work/notes.md"
manifest="$out/update.json"
"$tool" manifest --version "$version" --build "$build" --minimum-system-version "$min_os" \
    --notes-file "$notes_file" --zip "$zip" --dmg "$dmg" --signature "$signature" --key-id "$key_id" \
    --public-key "$public_key" > "$manifest" 2> "$logs/manifest.err" || \
    fail "Could not write update.json." "$(cat "$logs/manifest.err")"
( cd "$out" && shasum -a 256 "Tactile-$version.zip" "Tactile-$version.dmg" > SHA256SUMS )
( cd "$out" && shasum -a 256 -c SHA256SUMS > /dev/null 2>&1 ) || fail "SHA256SUMS does not check against the files."
# update.json against shasum and the files' sizes: two separate readings must agree.
zip_sum="$(awk -v n="Tactile-$version.zip" '$2 == n { print $1 }' "$out/SHA256SUMS")"
dmg_sum="$(awk -v n="Tactile-$version.dmg" '$2 == n { print $1 }' "$out/SHA256SUMS")"
[[ "$(json_value "$manifest" schema)" == "1" && "$(json_value "$manifest" version)" == "$version" &&
    "$(json_value "$manifest" build)" == "$build" &&
    "$(json_value "$manifest" minimumSystemVersion)" == "$min_os" &&
    "$(json_value "$manifest" archive.name)" == "Tactile-$version.zip" &&
    "$(json_value "$manifest" archive.size)" == "$(size_of "$zip")" &&
    "$(json_value "$manifest" archive.sha256)" == "$zip_sum" &&
    "$(json_value "$manifest" archive.signature)" == "$signature" &&
    "$(json_value "$manifest" archive.keyId)" == "$key_id" &&
    "$(json_value "$manifest" dmg.name)" == "Tactile-$version.dmg" &&
    "$(json_value "$manifest" dmg.size)" == "$(size_of "$dmg")" &&
    "$(json_value "$manifest" dmg.sha256)" == "$dmg_sum" ]] || \
    fail "update.json does not agree with the files (read back with plutil, against shasum and their sizes)."
info "update.json and SHA256SUMS written, and they agree with the files."

# --- Publishing ---------------------------------------------------------------------------------

assets=("$zip" "$dmg" "$manifest" "$out/SHA256SUMS")
step "Publishing release $tag"
if $dry_run; then
    would "run: gh release create $tag --repo $GITHUB_REPO --title 'Tactile $version' \\"
    info "            --notes-file <the notes> --verify-tag Tactile-$version.zip Tactile-$version.dmg update.json SHA256SUMS"
    would "then check that the release is published (not a draft) with those four files"
else
    publishing=true
    if ! gh release create "$tag" --repo "$GITHUB_REPO" --title "Tactile $version" --notes-file "$work/notes.md" \
            --verify-tag "${assets[@]}" > "$logs/gh-release.log" 2>&1; then
        fail "gh release create failed." "What it said: $(tail -n 5 "$logs/gh-release.log")"
    fi
    published="$(gh release view "$tag" --repo "$GITHUB_REPO" --json isDraft,assets \
        --jq '(.isDraft | tostring) + " " + ([.assets[].name] | sort | join(" "))' 2> /dev/null)" || published=""
    expected="false SHA256SUMS Tactile-$version.dmg Tactile-$version.zip update.json"
    [[ "$published" == "$expected" ]] || \
        fail "The release was created, but GitHub does not show it as expected." "It shows: ${published:-nothing}" "Expected: $expected"
    publishing=false
    info "Published: $(sed -n 's/^\(https:[^ ]*\).*/\1/p' "$logs/gh-release.log" | tail -n 1)"
fi

# --- What next ----------------------------------------------------------------------------------

describe_assets() {
    local file
    for file in "${assets[@]}"; do
        printf '  %-22s %s\n' "${file##*/}" "$(human_size "$(size_of "$file")")"
    done
}
if $dry_run; then
    step "Dry run finished: Tactile $version (build $build), built from $short, signed and checked"
    printf '\nNot done in a dry run: notarizing and stapling the app and the disk image, and publishing.\n'
    if [[ ${#reported[@]} -gt 0 ]]; then
        printf 'A real run would have stopped at:\n'
        for line in "${reported[@]}"; do printf '  - %s\n' "$line"; done
    fi
    printf '\nA real run would publish release %s to %s (not a draft), with:\n' "$tag" "$GITHUB_REPO"
    describe_assets
    printf '\nupdate.json (this dry run'"'"'s):\n'
    sed 's/^/  /' "$manifest"
    printf '\nThis dry run'"'"'s files (not notarized: never publish them) are in:\n  %s\n' "$out"
else
    step "Released: Tactile $version (build $build), built from $short, as $tag"
    printf '\nPublished to %s:\n' "$GITHUB_REPO"
    describe_assets
    printf '\nThe website offers it once it sees the release, within about 10 minutes (the site and its CDN each cache for up to 5 minutes):\n'
    printf '  https://tactilemac.com/api/mac/update\n'
    printf '\nThe files are also in:\n  %s\n' "$out"
fi
printf 'Logs: %s\nThe archive, with its dSYMs (keep it to read crash reports from this build):\n  %s\n' "$logs" "$archive"
finished=true
