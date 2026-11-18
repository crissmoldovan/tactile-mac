#!/usr/bin/env bash
# Tests the signing helpers of install.sh (and the Developer ID choice that release.sh shares):
#   - the Developer ID is found in what security find-identity prints, and nothing else counts;
#   - after a renewal (two valid certificates with the Developer ID's name), the one that expires
#     last is chosen, by its SHA-1, in install.sh and in release.sh, and what each says about its
#     choice (when the certificate expires, or that it could not be read); these run under the
#     current locale and again under ro_RO.UTF-8 and de_DE.UTF-8, which name the months otherwise;
#   - the build settings: the chosen certificate without a secure timestamp, or, without the
#     Developer ID, Apple Development;
#   - a designated requirement is read as codesign -d -r- prints it;
#   - a Tactile in /Applications signed differently from the new build gets the warning, in plain
#     words, with the advice to remove Tactile from the lists and add it again; one signed the same
#     way (the same designated requirement, even from other code) gets none;
#   - the warning for a build without the Developer ID gives the same advice;
#   - a command still running at the limit (as codesign is while a Keychain prompt waits) is stopped.
# It sources install.sh, which then only defines its functions, and release.sh in another bash, which
# does the same: nothing is built, and nothing in /Applications or the keychain is read or changed.
# The stand-in apps are made in a new folder in $TMPDIR, removed at the end, and signed ad hoc
# (codesign --sign -, which uses no key and no network), carrying the designated requirements of a
# Developer ID build and of an Apple Development one. The stand-in certificates are self-signed there
# by openssl, their keys thrown away at once.
# Usage: Tools/install-signing-tests.sh. Exit status 0 when every check passes.
set -euo pipefail

tools="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=install.sh
source "$tools/install.sh"
set -euo pipefail

# The designated requirements of the two kinds of build, as codesign -d -r- prints them. The Developer
# ID one is what Xcode makes for a Developer ID signature (0.6.0, as released, has it); the Apple
# Development one is what it makes for an Apple Development certificate, with a made-up name.
readonly DEVELOPER_ID_REQUIREMENT='anchor apple generic and identifier "com.crissmoldovan.tactile" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "75K3LTUM8A")'
readonly APPLE_DEVELOPMENT_REQUIREMENT='identifier "com.crissmoldovan.tactile" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: A Developer (ABCDE12345)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */'

passed=0
failed=0
check() {  # check <what> <command...>: passes when the command succeeds
    local what="$1"
    shift
    if "$@"; then
        passed=$(( passed + 1 ))
        printf 'ok    %s\n' "$what"
    else
        failed=$(( failed + 1 ))
        printf 'FAIL  %s\n' "$what"
    fi
}
not() { ! "$@"; }
equal() { [[ "$1" == "$2" ]]; }
has() { [[ "$1" == *"$2"* ]]; }
empty() { [[ -z "$1" ]]; }
starts() { [[ "$1" == "$2"* ]]; }

# Sourcing ran none of the script: no trap, and none of its state.
check "sourcing install.sh sets no trap" empty "$(trap -p EXIT)"
check "sourcing install.sh runs none of it" empty "${work+set}${lock_held+set}${dry_run+set}"

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/tactile-signing-tests.XXXXXX")"
trap 'rm -rf "$sandbox"' EXIT

make_app() {  # make_app <name> <executable to copy> [<designated requirement>]: an app signed ad hoc
    local app="$sandbox/$1"
    mkdir -p "$app/Contents/MacOS"
    cp "$2" "$app/Contents/MacOS/Tactile"
    cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Tactile</string>
    <key>CFBundleIdentifier</key><string>com.crissmoldovan.tactile</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST
    if [[ $# -ge 3 ]]; then
        codesign --force --sign - --timestamp=none -r="designated => $3" "$app" 2> /dev/null ||
            { printf 'could not sign the stand-in %s\n' "$1" >&2; exit 1; }
    else
        codesign --force --sign - --timestamp=none "$app" 2> /dev/null ||
            { printf 'could not sign the stand-in %s\n' "$1" >&2; exit 1; }
    fi
}
make_app developer-id.app /usr/bin/true "$DEVELOPER_ID_REQUIREMENT"
make_app developer-id-other-code.app /usr/bin/false "$DEVELOPER_ID_REQUIREMENT"
make_app apple-development.app /usr/bin/true "$APPLE_DEVELOPMENT_REQUIREMENT"
make_app ad-hoc.app /usr/bin/true
mkdir -p "$sandbox/unsigned.app/Contents/MacOS"
printf '#!/bin/sh\n' > "$sandbox/unsigned.app/Contents/MacOS/Tactile"

flat() {  # flat <file>: what a warning printed, as one line, without "warning:" and the indents
    sed -e 's/^ *warning: //' -e 's/^ *//' "$1" | tr '\n' ' '
}
compare() {  # compare <installed app> <new app>: compare_with_installed; what it printed in $out and $err
    compare_with_installed "$sandbox/$1" "$sandbox/$2" > "$sandbox/out" 2> "$sandbox/err"
    out="$(flat "$sandbox/out")"
    err="$(flat "$sandbox/err")"
}

# --- The Developer ID among the identities ------------------------------------------------------

listing="  1) 1111111111111111111111111111111111111111 \"Apple Development: A Developer (ABCDE12345)\"
  2) 2222222222222222222222222222222222222222 \"Developer ID Application: CRISTIAN MOLDOVAN (75K3LTUM8A)\"
     2 valid identities found"
check "the Developer ID is found among the identities" has_developer_id "$listing"
check "Apple Development alone is not the Developer ID" not has_developer_id \
    "  1) 1111111111111111111111111111111111111111 \"Apple Development: A Developer (ABCDE12345)\""
check "another team's Developer ID is not this one" not has_developer_id \
    "  1) 3333333333333333333333333333333333333333 \"Developer ID Application: Someone Else (ZZZZZ99999)\""
check "nothing printed is no Developer ID" not has_developer_id ""

# --- Reading a designated requirement -----------------------------------------------------------

requirement="$(designated_requirement "$sandbox/developer-id.app")" || requirement=""
check "a designated requirement is read as codesign prints it" equal "$requirement" "$DEVELOPER_ID_REQUIREMENT"
requirement="$(designated_requirement "$sandbox/ad-hoc.app")" || requirement=""
check "an implicit one (ad hoc) is read without its '# '" starts "$requirement" 'cdhash H"'
requirement="$(designated_requirement "$sandbox/unsigned.app")" || requirement=""
check "an unsigned app has none" empty "$requirement"

# --- Comparing with the Tactile in /Applications ------------------------------------------------

compare apple-development.app developer-id.app
check "Apple Development installed, Developer ID built: the signing changed" equal "$signing_changed" true
check "... it says so in plain words" has "$err" "the Tactile in $APPS_DIR is signed differently from the one just built."
check "... it says macOS may keep the old Accessibility and Input Monitoring entries" \
    has "$err" "macOS may keep Tactile's Accessibility and Input Monitoring entries for the old signature."
check "... and, if Tactile then says access is missing, to remove Tactile and add it again" \
    has "$err" "If Tactile then says Accessibility access is missing while it is switched on there, remove Tactile from both lists in System Settings › Privacy & Security with −, and add it again with +."
check "... and shows the installed copy's designated requirement" \
    has "$out" "Designated requirement in $APPS_DIR: $APPLE_DEVELOPMENT_REQUIREMENT"
check "... and never says it is signed the same way" not has "$out" "Signed the same way"

compare developer-id.app apple-development.app
check "Developer ID installed, Apple Development built: the signing changed too" equal "$signing_changed" true
check "... with the same advice" has "$err" "with −, and add it again with +."

compare developer-id.app developer-id-other-code.app
check "the same designated requirement, other code: the signing did not change" equal "$signing_changed" false
check "... it says it is signed the same way" \
    has "$out" "Signed the same way as the Tactile in $APPS_DIR: the same designated requirement."
check "... and warns of nothing" empty "$err"

compare ad-hoc.app developer-id.app
check "ad hoc installed: the signing changed" equal "$signing_changed" true
check "... and it says the installed copy was signed ad hoc" has "$err" "The one in $APPS_DIR: signed ad hoc, by no one."

compare unsigned.app developer-id.app
check "an installed copy whose signature can't be read counts as signed differently" equal "$signing_changed" true
check "... and it says so" has "$err" "The one in $APPS_DIR: its signature can't be read."
check "... with the same advice" has "$err" "with −, and add it again with +."

# --- A build without the Developer ID -----------------------------------------------------------

warn_signed_unlike_releases > "$sandbox/out" 2> "$sandbox/err"
err="$(flat "$sandbox/err")"
check "without the Developer ID: it says the build is signed unlike the releases" \
    has "$err" "the Developer ID is not in this Mac's keychain, or is not valid, so this build is signed with Apple Development, not as the downloaded releases are."
check "... that switching may leave a stale Accessibility and Input Monitoring entry" \
    has "$err" "may make macOS keep a stale Accessibility and Input Monitoring entry: Tactile looks switched on there, but is refused."
check "... and, if so, to remove Tactile and add it again" \
    has "$err" "If so, remove Tactile from both lists in System Settings › Privacy & Security with −, and add it again with +."
check "... on stderr only" empty "$(cat "$sandbox/out")"

# --- After a renewal: the Developer ID that expires last ----------------------------------------

make_certificate() {  # make_certificate <name> <days> <common name>: a self-signed certificate, in
    # <name>.pem, valid for <days>; its key goes nowhere. Prints its SHA-1.
    openssl req -x509 -newkey rsa:2048 -nodes -days "$2" -subj "/CN=$3/OU=$TEAM_ID" \
        -keyout /dev/null -out "$sandbox/$1.pem" 2> /dev/null ||
        { printf 'could not make the stand-in certificate %s\n' "$1" >&2; exit 1; }
    openssl x509 -noout -fingerprint -sha1 -in "$sandbox/$1.pem" | sed 's/^.*=//; s/://g'
}
listed() {  # listed <SHA-1> <PEM name>: one certificate as security find-certificate -a -Z -p prints it
    printf 'SHA-256 hash: %s\n' "$(openssl x509 -noout -fingerprint -sha256 -in "$sandbox/$2.pem" | sed 's/^.*=//; s/://g')"
    printf 'SHA-1 hash: %s\n' "$1"
    cat "$sandbox/$2.pem"
}
identity() { printf '  %s) %s "%s"\n' "$1" "$2" "$3"; }   # identity <n> <SHA-1> <name>: a find-identity line

old_hash="$(make_certificate old 400 "$IDENTITY")"
new_hash="$(make_certificate new 800 "$IDENTITY")"
other_name="Developer ID Application: Someone Else (ZZZZZ99999)"
other_hash="$(make_certificate other 1200 "$other_name")"
certificates="$(listed "$old_hash" old; listed "$new_hash" new; listed "$other_hash" other)"
apple_development="$(identity 1 1111111111111111111111111111111111111111 "Apple Development: A Developer (ABCDE12345)")"

in_release() {  # in_release <command...>: runs it in a new bash that has sourced release.sh
    bash -c 'source "$1" || exit 99; shift; "$@"' in_release "$tools/release.sh" "$@"
}
# shellcheck disable=SC2016  # expanded by the inner bash
check "sourcing release.sh runs none of it" \
    in_release eval '[[ -z "${dry_run+set}${notes_file+set}${work+set}" && -z "$(trap -p EXIT)" ]]'
in_copy() {  # in_copy <install.sh|release.sh> <command...>: runs one of that script's helpers
    local copy="$1"
    shift
    if [[ "$copy" == install.sh ]]; then "$@"; else in_release "$@"; fi
}
until_date() {  # until_date <PEM name>: when it expires, as "17 Nov 2031", from openssl's own words
    local month day year _
    read -r month day _ year _ <<< "$(openssl x509 -noout -enddate -in "$sandbox/$1.pem" | sed 's/^notAfter=//')"
    printf '%s %s %s\n' "$day" "$month" "$year"
}
old_until="$(until_date old)"
new_until="$(until_date new)"
renewed="$(identity 1 "$old_hash" "$IDENTITY"; identity 2 "$new_hash" "$IDENTITY")"
twice="$(identity 1 "$old_hash" "$IDENTITY"; identity 2 "$old_hash" "$IDENTITY")"   # in two keychains
only_old="$(listed "$old_hash" old)"

renewal_checks() {  # renewal_checks <label>: the checks of the choice after a renewal, in the locale set
    local in="$1" copy
    expiry="$(certificate_expiry "$(cat "$sandbox/new.pem")")"
    soon=$(( $(date +%s) + 800 * 86400 ))
    check "a certificate's expiry is read (800 days from now)$in" \
        test "${expiry:-0}" -ge $(( soon - 86400 )) -a "${expiry:-0}" -le $(( soon + 86400 ))
    check "a certificate's PEM is found by its SHA-1$in" \
        equal "$(certificate_of "$old_hash" "$certificates")" "$(cat "$sandbox/old.pem")"
    check "an unknown SHA-1 has no PEM$in" empty "$(certificate_of 0000000000000000000000000000000000000000 "$certificates")"
    for copy in install.sh release.sh; do
        check "$copy: one Developer ID: that one$in" \
            equal "$(in_copy "$copy" newest_developer_id "$(identity 1 "$old_hash" "$IDENTITY")" "$certificates")" "$old_hash"
        check "$copy: one Developer ID whose certificate can't be read: that one all the same$in" \
            equal "$(in_copy "$copy" newest_developer_id "$(identity 1 "$old_hash" "$IDENTITY")" "")" "$old_hash"
        check "$copy: renewed, the old one listed first: the one that expires last$in" \
            equal "$(in_copy "$copy" newest_developer_id "$renewed" "$certificates")" "$new_hash"
        check "$copy: renewed, the new one listed first: the one that expires last$in" \
            equal "$(in_copy "$copy" newest_developer_id "$(identity 1 "$new_hash" "$IDENTITY"; identity 2 "$old_hash" "$IDENTITY")" "$certificates")" "$new_hash"
        check "$copy: renewed, but no certificate can be read: the first listed$in" \
            equal "$(in_copy "$copy" newest_developer_id "$renewed" "")" "$old_hash"
        check "$copy: renewed, only the old one's expiry can be read: that one$in" \
            equal "$(in_copy "$copy" newest_developer_id "$renewed" "$only_old")" "$old_hash"
        check "$copy: one certificate listed twice (in two keychains): that one$in" \
            equal "$(in_copy "$copy" newest_developer_id "$twice" "$certificates")" "$old_hash"
        check "$copy: another team's Developer ID, though it expires later, is never chosen$in" \
            equal "$(in_copy "$copy" newest_developer_id "$(identity 1 "$other_hash" "$other_name"; identity 2 "$old_hash" "$IDENTITY")" "$certificates")" "$old_hash"
        check "$copy: Apple Development alone: none$in" empty "$(in_copy "$copy" newest_developer_id "$apple_development" "$certificates")"
        check "$copy: nothing listed: none$in" empty "$(in_copy "$copy" newest_developer_id "" "$certificates")"

        # What it says about its choice.
        in_copy "$copy" describe_choice "$renewed" "$certificates" "$new_hash" > "$sandbox/out" 2> "$sandbox/err"
        out="$(flat "$sandbox/out")"
        err="$(flat "$sandbox/err")"
        check "$copy: renewed: it says so$in" \
            has "$out" "2 valid certificates have that name (a renewal): it signs with the one that expires last."
        check "$copy: ... names the certificate and when it expires$in" \
            has "$out" "Its certificate: SHA-1 $new_hash, valid until $new_until"
        check "$copy: ... and warns of nothing$in" empty "$err"
        in_copy "$copy" describe_choice "$twice" "$certificates" "$old_hash" > "$sandbox/out" 2> "$sandbox/err"
        out="$(flat "$sandbox/out")"
        check "$copy: one certificate listed twice is not called a renewal$in" not has "$out" "a renewal"
        check "$copy: ... and its expiry is given$in" has "$out" "Its certificate: SHA-1 $old_hash, valid until $old_until"
        in_copy "$copy" describe_choice "$renewed" "" "$old_hash" > "$sandbox/out" 2> "$sandbox/err"
        out="$(flat "$sandbox/out")"
        err="$(flat "$sandbox/err")"
        check "$copy: renewed, no expiry readable: it warns that it signs with the first one listed$in" \
            has "$err" "none of their expiry dates could be read, so it signs with the first one listed, which may not be the one that expires last."
        check "$copy: ... and says the chosen one's expiry could not be read$in" \
            has "$out" "Its certificate: SHA-1 $old_hash; its expiry could not be read"
        in_copy "$copy" describe_choice "$renewed" "$only_old" "$old_hash" > "$sandbox/out" 2> "$sandbox/err"
        err="$(flat "$sandbox/err")"
        check "$copy: renewed, one expiry not readable: it warns that the choice may be wrong$in" \
            has "$err" "the expiry date of 1 of them could not be read, so the one chosen may not be the one that expires last."
    done
}

renewal_checks ""
# The month in openssl's date is English: it must be read so under any locale (and with GNU date
# earlier in PATH). Once more, under two locales that name the months otherwise.
locales="$(locale -a 2> /dev/null)" || locales=""
had_lc_all="${LC_ALL+set}"
saved_lc_all="${LC_ALL-}"
for locale in ro_RO.UTF-8 de_DE.UTF-8; do
    if ! grep -qx "$locale" <<< "$locales"; then
        printf 'skip  the renewal checks under LC_ALL=%s: this Mac has no such locale\n' "$locale"
        continue
    fi
    export LC_ALL="$locale"
    renewal_checks " (LC_ALL=$locale)"
done
if [[ -n "$had_lc_all" ]]; then export LC_ALL="$saved_lc_all"; else unset LC_ALL; fi

# --- The build settings -------------------------------------------------------------------------

# All of it given on the command line, so a build doesn't depend on the project's signing (ad hoc,
# unless a git-ignored Signing.local.xcconfig says otherwise).
signing_settings "$new_hash"
check "with the Developer ID: manual signing, the team, the chosen certificate by its SHA-1, no secure timestamp" \
    equal "$(printf '%s|' "${signing[@]}")" \
    "CODE_SIGN_STYLE=Manual|DEVELOPMENT_TEAM=75K3LTUM8A|CODE_SIGN_IDENTITY=$new_hash|PROVISIONING_PROFILE_SPECIFIER=|OTHER_CODE_SIGN_FLAGS=--timestamp=none|"
signing_settings ""
check "without it: Apple Development for the team, as the project signed before 0.6.1" \
    equal "$(printf '%s|' "${signing[@]}")" \
    "CODE_SIGN_STYLE=Automatic|DEVELOPMENT_TEAM=75K3LTUM8A|CODE_SIGN_IDENTITY=Apple Development|"

# --- The time limit -----------------------------------------------------------------------------

status=0; run_limited 5 true || status=$?
check "a command that ends in time: its status (0)" equal "$status" 0
status=0; run_limited 5 false || status=$?
check "a command that ends in time: its status (1)" equal "$status" 1
started=$SECONDS
status=0
# shellcheck disable=SC2016  # $$ and $1 are the inner shell's
run_limited 1 /bin/bash -c 'echo $$ > "$1"; exec /bin/sleep 30' limited "$sandbox/pid" || status=$?
took=$(( SECONDS - started ))
check "a command still running at the limit is stopped: 124" equal "$status" 124
check "... at the limit, not when it ends (${took}s)" test "$took" -le 5
check "... and it is gone" not kill -0 "$(cat "$sandbox/pid")" 2> /dev/null
check "... and nothing is left to stop on the way out" empty "$child"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
