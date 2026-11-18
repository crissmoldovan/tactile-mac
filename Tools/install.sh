#!/usr/bin/env bash
# Builds Tactile (Release) from this repository and installs it as /Applications/Tactile.app.
# Run it as yourself, without sudo. `Tools/install.sh --help` says what it does.
set -euo pipefail

readonly BUNDLE_ID="com.crissmoldovan.tactile"
readonly APPS_DIR="/Applications"
readonly TARGET="$APPS_DIR/Tactile.app"
readonly QUIT_WAIT_SECONDS=10
readonly LOCK_PATH="${HOME:?HOME is not set}/Library/Caches/$BUNDLE_ID.install.lock"
# The identity this script and release.sh sign with, and the maintainer's own builds through the
# git-ignored Config/Signing.local.xcconfig (the project alone signs ad hoc). Builds signed with it
# share one designated requirement, so macOS's privacy permissions carry over.
readonly TEAM_ID="75K3LTUM8A"
readonly IDENTITY="Developer ID Application: CRISTIAN MOLDOVAN ($TEAM_ID)"
readonly SIGNING_WAIT_SECONDS=120

usage() {
    cat <<'EOF'
usage: Tools/install.sh [--dry-run] [--quit-running]
       Tools/install.sh --help

Builds Tactile's Release configuration from this checkout as it is (uncommitted changes included:
it says so), in a new scratch folder in $TMPDIR that is removed at the end (never the Mac app's
build/ folder), checks the app it built, and installs it as /Applications/Tactile.app.

The checks: its version (printed), its signature (codesign --verify --deep --strict), who signed it
(the Developer ID, when it signed with it), the hardened runtime, and no sandbox entitlement. If any
fails, nothing is installed. It prints the designated requirement too.

How it signs: with the Developer ID, "Developer ID Application: CRISTIAN MOLDOVAN (75K3LTUM8A)",
as the downloaded releases are, and as Debug builds from Xcode are when the git-ignored
Config/Signing.local.xcconfig says so (without it the project signs ad hoc). It gives
the signing settings to xcodebuild itself, so it doesn't depend on that file. Builds signed with
the Developer ID have the same designated requirement, so macOS keeps Tactile's Accessibility and
Input Monitoring permissions when you switch from one to another. If more than one valid certificate of
that name is in the keychain (after a renewal), it signs with the one that expires last. No secure
timestamp is asked of Apple's server (a local build is never notarized), so it builds offline.

Before building, it signs a scratch file with that certificate's key. If codesign has not finished
after 120 seconds, macOS is probably showing a Keychain prompt for the key: it stops and says so.
Answer the prompt with Always Allow, then run it again.

If no valid Developer ID is in the keychain (security find-identity -v -p codesigning), as on
another Mac, it signs this build with Apple Development instead (CODE_SIGN_STYLE=Automatic
DEVELOPMENT_TEAM=75K3LTUM8A CODE_SIGN_IDENTITY="Apple Development"), and warns that it is signed
differently from the downloaded releases. If the Tactile in /Applications is signed differently
from the new build (their designated requirements, codesign -d -r-, are not the same), it says so
before replacing it, and installs it all the same. After such a switch macOS may keep a stale
Accessibility and Input Monitoring entry: Tactile looks switched on there, but is refused. If so,
remove Tactile from both lists in System Settings › Privacy & Security with −, and add it again
with +.

How it installs: the new app is copied next to the old one, as Tactile.app.installing-<pid>, and
checked there (signature, identifier, version, and that it is the app just built). Only then is the
old Tactile.app (checked again: still this Tactile) renamed aside and the checked copy renamed into
its place. The old one is removed only once what has the name Tactile.app is confirmed to carry the
checked copy's code-directory hash; if that can't be confirmed (a hash that can't be read counts as
not confirmed), the old one is kept aside, and its place and the mv that puts it back are printed
(exit 3). The old Tactile.app is not touched until a checked copy is ready.

If it fails or is interrupted (Ctrl-C, Ctrl-\, SIGTERM, the terminal closed) before the checked copy
has the name Tactile.app, it removes its copy and, if the old app had been renamed aside, renames it
back. If that happens once the checked copy has the name, it finishes the install instead, with the
same confirmation before the old one is removed. It says what it did, except after the terminal was
closed: then nothing can be shown, but the same is done.

What a run can leave behind, and where:
  /Applications/Tactile.app.installing-<pid>
      its copy: after a run that was killed (kill -9, a crash, a power cut), or when the copy
      could not be removed (it says so). A copy of the new build: safe to delete; the next run
      removes it.
  /Applications/Tactile.app.replaced-<time>-<pid>
      the old app, in four cases: after a run killed between the two renames (then there is no
      Tactile.app; the next run stops and prints the mv that puts it back); after a run killed once
      the new copy had the name but before the old one was removed (beside a working Tactile.app;
      the next run warns and leaves it); after exit 3 (the mv was printed); or when it could not be
      removed after installing (it says so).
  ~/Library/Caches/com.crissmoldovan.tactile.install.lock
      the lock of a run that was killed: the next run sees that run has gone and takes it over.
      If the process number of that run now belongs to another program, the next run stops and
      names the number and the lock: check that no install is running, delete the lock, and run
      again.
  $TMPDIR/tactile-install.XXXXXX
      the build folder of a run that was killed: the next run removes it.
  $TMPDIR/tactile-install-build.log
      the log of a build that failed.

If Tactile is running, it stops before building, unless the following is given; if that Tactile is
another user's, it stops even then, as it can't quit it:
  --quit-running   once the new copy has passed its checks, ask the running Tactile to quit
                   (SIGTERM, the ordinary way: it lets the touchscreens go), wait up to 10
                   seconds, and stop if it is still running. Nothing is ever force-quit, and
                   Tactile is not started again afterwards.

  --dry-run        build and check, and print what would be done; nothing in /Applications is
                   changed and nothing is quit.
  -h, --help       this text.

One run at a time: the lock is ~/Library/Caches/com.crissmoldovan.tactile.install.lock.

Exit status:
  0  installed (with --dry-run: nothing in the way)
  1  stopped before changing Tactile.app (at most, what an earlier run left was removed): a bad
     option, a failed check or build, another run going on, Tactile running, something left by an
     earlier run, or Tactile.app changed while it ran
  2  the install failed or was interrupted, and the old Tactile is in place (put back, or never
     moved)
  3  the old Tactile could not be put back (also when what has the name Tactile.app could not be
     confirmed to be the new copy: the old one is then kept aside); where it is, and the mv that
     puts it back, were printed
EOF
}

# --- Output -------------------------------------------------------------------------------------

explained=false   # a message has said why it stopped
step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
would() { printf '    [dry run] would %s\n' "$*"; }
warn() {  # warn <line> [<more lines>...]: the first after "warning:", the rest lined up beneath it
    printf '    warning: %s\n' "$1" >&2
    shift
    local line
    for line in "$@"; do printf '             %s\n' "$line" >&2; done
}
fail() {  # stop before anything in /Applications was changed (exit 1)
    explained=true
    printf '\ninstall.sh: %s\n' "$1" >&2
    shift
    local line
    for line in "$@"; do printf '    %s\n' "$line" >&2; done
    exit 1
}
stop_reason=""
stop_code=""
stop_install() {  # the install failed part-way: on_exit puts things back and says what it did
    stop_reason="$1"
    exit 2
}
stop_unchanged() {  # stop during the install, Tactile.app not touched by design: on_exit removes the copy (exit 1)
    stop_reason="$1"
    stop_code=1
    exit 1
}

# --- Signing ------------------------------------------------------------------------------------
# These read and print, and change nothing. install-signing-tests.sh tests them.

has_developer_id() {  # has_developer_id <what security find-identity -v -p codesigning printed>
    grep -qF "\"$IDENTITY\"" <<< "$1"
}

# A renewed certificate has the same name as the old one, and both are valid for a while, so the name
# alone is ambiguous to codesign. The one that expires last is chosen, by its SHA-1. The designated
# requirement names the team, not the certificate, so it is the same with either.
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

signing=()   # the build settings given to xcodebuild for this build only
signing_settings() {  # signing_settings <SHA-1 of the Developer ID, or nothing>: sets signing
    # All of it is given here, so the build doesn't depend on the project's signing, which is ad hoc
    # unless the git-ignored Signing.local.xcconfig says otherwise.
    if [[ -n "$1" ]]; then
        # Manual signing with the Developer ID: the certificate by its SHA-1 (the newest, after a
        # renewal), and no secure timestamp.
        signing=(CODE_SIGN_STYLE=Manual "DEVELOPMENT_TEAM=$TEAM_ID" "CODE_SIGN_IDENTITY=$1"
            PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp=none)
    else
        # Without it, Apple Development for the team, as the project signed before 0.6.1.
        signing=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$TEAM_ID" "CODE_SIGN_IDENTITY=Apple Development")
    fi
}

designated_requirement() {  # designated_requirement <code>: its designated requirement, or nothing
    # codesign prints "designated => ...", after "# " when the requirement is implicit (ad hoc).
    codesign -d -r- "$1" 2> /dev/null | sed -n 's/^# *//; s/^designated => //p' | head -n 1
}

signed_by() {  # signed_by <code>: who signed it (its signature's first Authority), or nothing
    codesign -dvv "$1" 2>&1 | sed -n 's/^Authority=//p' | head -n 1
}

signing_changed=false   # the Tactile in /Applications is signed differently from the new build
compare_with_installed() {  # compare_with_installed <installed app> <new app>: says whether they are
    # signed alike (the same designated requirement), and sets signing_changed
    local old_requirement new_requirement old_signer new_signer
    old_requirement="$(designated_requirement "$1")" || old_requirement=""
    new_requirement="$(designated_requirement "$2")" || new_requirement=""
    if [[ -n "$old_requirement" && "$old_requirement" == "$new_requirement" ]]; then
        signing_changed=false
        info "Signed the same way as the Tactile in $APPS_DIR: the same designated requirement."
        return 0
    fi
    signing_changed=true
    old_signer="$(signed_by "$1")" || old_signer=""
    new_signer="$(signed_by "$2")" || new_signer=""
    if [[ -z "$old_requirement" ]]; then
        old_signer="its signature can't be read"
    elif [[ -z "$old_signer" ]]; then
        old_signer="signed ad hoc, by no one"
    else
        old_signer="signed by $old_signer"
    fi
    if [[ -z "$new_signer" ]]; then new_signer="signed ad hoc, by no one"; else new_signer="signed by $new_signer"; fi
    warn "the Tactile in $APPS_DIR is signed differently from the one just built." \
        "The one in $APPS_DIR: $old_signer." \
        "The one just built: $new_signer." \
        "macOS may keep Tactile's Accessibility and Input Monitoring entries for the old signature." \
        "If Tactile then says Accessibility access is missing while it is switched on there, remove" \
        "Tactile from both lists in System Settings › Privacy & Security with −, and add it again" \
        "with +."
    if [[ -n "$old_requirement" ]]; then info "Designated requirement in $APPS_DIR: $old_requirement"; fi
}

warn_signed_unlike_releases() {  # the build signs with Apple Development, not the Developer ID
    warn "the Developer ID is not in this Mac's keychain, or is not valid, so this build is signed" \
        "with Apple Development, not as the downloaded releases are. Switching between this build" \
        "and a downloaded release, either way, may make macOS keep a stale Accessibility and Input" \
        "Monitoring entry: Tactile looks switched on there, but is refused. If so, remove Tactile" \
        "from both lists in System Settings › Privacy & Security with −, and add it again with +."
}

child=""   # a codesign started by run_limited, which must not outlive the run
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

# Sourced (by install-signing-tests.sh), it stops here, having only defined what is above.
(return 0 2> /dev/null) && return 0

# --- Arguments ----------------------------------------------------------------------------------

dry_run=false
quit_running=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true ;;
        --quit-running) quit_running=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install.sh: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# The Mac app's folder (the repository's root) is the folder above this script's own (through any
# symbolic links to it).
script="${BASH_SOURCE[0]}"
while [[ -L "$script" ]]; do
    link_dir="$(cd -P "$(dirname "$script")" && pwd)"
    script="$(readlink "$script")"
    [[ "$script" == /* ]] || script="$link_dir/$script"
done
repo="$(cd -P "$(dirname "$script")/.." && pwd)"
project="$repo/Tactile.xcodeproj"
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"

# --- State, and putting things right on the way out ---------------------------------------------

work=""                # the scratch folder for the build
lock_held=false
staging=""             # $APPS_DIR/Tactile.app.installing-$$: the new copy, until it is checked and swapped in
aside=""               # $APPS_DIR/Tactile.app.replaced-<time>-$$: the old app, between the two renames
old_existed=false      # there was a Tactile.app before this run
quit_asked=false       # this run asked a running Tactile to quit
quit_done=false        # ... and it has quit
quit_pids=()
finished=false         # the run reached its end and said so
built_version=""
# idle -> copying -> verifying -> moving-old -> moving-new -> placed -> installed (or unconfirmed, when
# what is at the real name after the second rename is not the checked copy). Each is set before the
# step it names, so an interruption is always handled; on_exit then acts on what is on disk.
replace_state="idle"

say() {  # a message on the way out: a closed terminal or a broken pipe must not stop the clean-up
    printf '%s\n' "$*" >&2 2> /dev/null || true
}
# on_exit runs no command substitution: after a write to a closed terminal or a broken pipe has
# failed, bash keeps the unwritten text, and a forked subshell would flush it into what it captures.

on_exit() {
    local status=$?
    trap '' INT TERM HUP QUIT PIPE
    set +e
    local code=0 outcome="" copy_left="" inside="" unconfirmed=false
    if [[ -n "$child" ]]; then kill -TERM "$child" 2> /dev/null; wait "$child" 2> /dev/null; fi

    # 1. Put things right on disk, before printing anything.
    case "$replace_state" in
        copying|verifying|moving-old|moving-new|placed|unconfirmed)
            if [[ -n "$staging" ]]; then
                inside="$TARGET/${staging##*/}"
                if [[ -e "$inside" || -L "$inside" ]]; then
                    # Something appeared at the real name and the checked copy went inside it: back out.
                    mv "$inside" "$staging" 2> /dev/null || copy_left="$inside"
                fi
            fi
            if [[ "$replace_state" == "moving-new" || "$replace_state" == "placed" ]] &&
                [[ -z "$copy_left" && -n "$staging" && ! -e "$staging" && ! -L "$staging" && -d "$TARGET" && ! -L "$TARGET" ]]; then
                # The second rename had happened. Installed only once what has the name is confirmed
                # to be the checked copy; until then the old app is kept.
                if confirmed_at_target; then replace_state="installed"; else replace_state="unconfirmed"; fi
            fi
            if [[ "$replace_state" == "unconfirmed" ]]; then unconfirmed=true; fi
            if [[ "$replace_state" != "installed" ]]; then
                if [[ -n "$staging" ]] && [[ -e "$staging" || -L "$staging" ]]; then
                    rm -rf "$staging"
                    if [[ -e "$staging" || -L "$staging" ]]; then copy_left="$staging"; fi
                fi
                if [[ -n "$aside" && -d "$aside" ]]; then
                    if [[ ! -e "$TARGET" && ! -L "$TARGET" ]] && mv "$aside" "$TARGET"; then
                        outcome="put-back"; code=2
                    else
                        outcome="not-put-back"; code=3
                    fi
                elif [[ "$replace_state" == "unconfirmed" ]]; then
                    outcome="unconfirmed"; code=2
                else
                    outcome="untouched"; code=2
                    if [[ -n "$stop_code" ]]; then code="$stop_code"; fi
                fi
            fi
            ;;
    esac
    if [[ "$replace_state" == "installed" ]]; then
        code=0
        outcome="installed"
        if [[ -n "$aside" && -d "$aside" ]] && ! rm -rf "$aside"; then
            outcome="installed-old-left"
        fi
    elif [[ "$replace_state" == "idle" && $status -ne 0 ]]; then
        code=1
    fi

    # 2. Then say what happened.
    if ! $finished; then
        local why="$stop_reason"
        if [[ -z "$why" ]]; then
            case "$status" in
                0) why="" ;;
                129) why="Stopped: the terminal was closed." ;;
                130) why="Interrupted (Ctrl-C)." ;;
                131) why="Interrupted (Ctrl-\\)." ;;
                141) why="Stopped: its output was cut off (a broken pipe)." ;;
                143) why="Stopped (SIGTERM)." ;;
                *) $explained || why="Stopped by an unexpected error (status $status)." ;;
            esac
        fi
        if [[ -n "$why" ]]; then say ""; say "install.sh: $why"; fi
        if [[ -n "$copy_left" ]]; then   # say what is true: the copy is still there
            if [[ "$copy_left" == "$staging" ]]; then
                say "    Its copy could not be removed: $copy_left"
                say "    It is a copy of the new build: safe to delete by hand, and the next run removes it."
            else
                say "    Its copy is stuck inside what appeared at $TARGET: $copy_left"
                say "    It is a copy of the new build: safe to delete by hand."
            fi
        fi
        case "$outcome" in
            "")
                if [[ $code -ne 0 ]] && ! $explained; then say "    Nothing in $APPS_DIR was changed."; fi ;;
            untouched)
                if [[ -n "$copy_left" ]]; then
                    if [[ -n "$stop_code" ]] || ! $old_existed; then
                        say "    $TARGET was not touched."
                    else
                        say "    The old Tactile in $APPS_DIR was not touched."
                    fi
                elif [[ -n "$stop_code" ]]; then
                    say "    Its copy was removed; $TARGET was not touched."
                elif $old_existed; then
                    say "    Its copy was removed; the old Tactile in $APPS_DIR was not touched."
                else
                    say "    Its copy was removed; nothing was installed, and $APPS_DIR is as it was."
                fi ;;
            unconfirmed)
                say "    What is at $TARGET was left as it is. There was no Tactile there before this run." ;;
            put-back)
                if [[ -n "$copy_left" ]]; then
                    say "    The old Tactile was put back as $TARGET, unchanged."
                else
                    say "    Its copy was removed, and the old Tactile was put back as $TARGET, unchanged."
                fi ;;
            not-put-back)
                local aside_q target_q
                printf -v aside_q '%q' "$aside"
                printf -v target_q '%q' "$TARGET"
                if $unconfirmed; then
                    say "    What has the name $TARGET is not confirmed to be the new copy, so it was left as it is."
                fi
                say "    The old Tactile could not be put back. It is at:"
                say "      $aside"
                say "    To put it back, once nothing else is at $TARGET:"
                say "      mv $aside_q $target_q" ;;
            installed|installed-old-left)
                say "    The new Tactile was already in place: $built_version is installed as $TARGET."
                if [[ "$outcome" == "installed-old-left" ]]; then
                    say "    The old copy could not be removed: $aside. Move it to the Bin in Finder."
                fi ;;
        esac
        if $quit_asked && ! $quit_done; then   # interrupted while waiting: has it gone? (kill is a builtin)
            quit_done=true
            local qp
            for qp in ${quit_pids[@]+"${quit_pids[@]}"}; do
                if kill -0 "$qp" 2> /dev/null; then quit_done=false; fi
            done
        fi
        if $quit_done && [[ "$outcome" != installed* ]]; then
            say "    Tactile was quit for the install and has not been started again: open it from Applications."
        fi
    fi

    # 3. Clean up.
    if [[ -n "$work" && -d "$work" ]]; then rm -rf "$work"; fi
    read_lock_holder
    if $lock_held && [[ "$lock_pid" == "$$" ]]; then rm -f "$LOCK_PATH"; fi
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

describe_app() {  # describe_app <app>: "Tactile 0.5.0 (build 1)"
    local plist="$1/Contents/Info.plist"
    printf 'Tactile %s (build %s)' "$(plist_value "$plist" CFBundleShortVersionString)" \
        "$(plist_value "$plist" CFBundleVersion)"
}

cdhash() {  # cdhash <app>: the code directory hash of its signature, or nothing
    codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1
}

confirmed_at_target() {  # what has the name Tactile.app carries the checked copy's code-directory hash.
    # A hash that can't be read is not a confirmation. No subshell, so on_exit can use it too.
    [[ -n "${copy_hash:-}" && -n "$work" && -d "$work" ]] || return 1
    codesign -dvvv "$TARGET" > "$work/confirm.txt" 2>&1 || return 1
    grep -qx "CDHash=$copy_hash" "$work/confirm.txt"
}

running_tactiles() {  # the process IDs of every running Tactile, one per line
    pgrep -x Tactile 2> /dev/null || true
}

describe_running() {
    local pid
    for pid in "$@"; do
        info "pid $pid: $(ps -o user= -p "$pid" 2> /dev/null | tr -d ' ') $(ps -o comm= -p "$pid" 2> /dev/null)"
    done
}

others_running() {  # sets others to "<user> (pid N)" for each of these Tactiles that another user runs
    local pid user
    others=""
    for pid in "$@"; do
        user="$(ps -o user= -p "$pid" 2> /dev/null | tr -d ' ')" || true
        if [[ -n "$user" && "$user" != "$me" ]]; then others="${others:+$others, }$user (pid $pid)"; fi
    done
}

read_lock_holder() {  # sets lock_pid to the process ID in the lock, or nothing (no subshell: see on_exit)
    lock_pid=""
    IFS= read -r lock_pid 2> /dev/null < "$LOCK_PATH" || true
    lock_pid="${lock_pid//[!0-9]/}"
}

take_lock() {  # shlock makes the lock in one step. macOS's shlock leaves a stale lock (its run has gone)
               # in place, so a stale one is taken over here by renaming it to a name of this run's
               # own: of several runs, only one can rename it.
    if /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null; then return 0; fi
    local holder renamed="" mine="$LOCK_PATH.stale-$$"
    read_lock_holder; holder="$lock_pid"
    if [[ -n "$holder" ]] && kill -0 "$holder" 2> /dev/null; then return 1; fi
    rm -f "$mine"
    if ! mv "$LOCK_PATH" "$mine" 2> /dev/null; then
        # Another run renamed it first and is about to take the lock: try once, as it does.
        /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null
        return
    fi
    # What was renamed must be the stale lock, not one another run took in the meantime.
    IFS= read -r renamed 2> /dev/null < "$mine" || true
    renamed="${renamed//[!0-9]/}"
    if [[ -n "$renamed" && "$renamed" != "$holder" ]] && kill -0 "$renamed" 2> /dev/null; then
        ln "$mine" "$LOCK_PATH" 2> /dev/null || true   # that run's lock: put it back
        rm -f "$mine"
        return 1
    fi
    rm -f "$mine"
    /usr/bin/shlock -p "$$" -f "$LOCK_PATH" 2> /dev/null
}

is_own_run() {  # is_own_run <pid>: that process is running this script (by its file or link name)
    local command
    kill -0 "$1" 2> /dev/null || return 1
    command="$(ps -o command= -p "$1" 2> /dev/null)" || return 1
    [[ "$command" == *"${script##*/}"* || "$command" == *"${0##*/}"* ]]
}

# --- Before building ----------------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "Tactile installs only on macOS."
[[ "$(id -u)" -ne 0 ]] || fail "Run this as yourself, not with sudo or as root." \
    "Tactile is installed with your own permissions, like dragging it to Applications in Finder."
for tool in xcodebuild codesign ditto pgrep /usr/bin/shlock; do
    command -v "$tool" > /dev/null || fail "$tool was not found. Install Xcode (and open it once) first."
done
[[ -d "$project" ]] || fail "No Tactile.xcodeproj in $repo."

if $dry_run; then
    printf 'Tactile installer: DRY RUN. /Applications will not be changed and nothing will be quit.\n'
else
    printf 'Tactile installer\n'
fi

mkdir -p "$(dirname "$LOCK_PATH")"
if ! take_lock; then
    read_lock_holder
    fail "Another run of this installer is going on (pid ${lock_pid:-unknown}). Wait for it to finish." \
        "Its lock is $LOCK_PATH."
fi
lock_held=true

me="$(id -un)"

# What earlier runs that were killed left behind. Holding the lock, none of it is in use. Only these
# names are ever removed: build folders tactile-install.XXXXXX (as mktemp makes them) in $TMPDIR, and
# copies Tactile.app.installing-<pid> in /Applications; real folders, never a link.
cleaned=false
left_kb=0
left_count=0
for old_work in "$tmp_root"/tactile-install.??????; do
    if [[ -d "$old_work" && ! -L "$old_work" ]]; then
        size="$(du -sk "$old_work" 2> /dev/null | cut -f1)" || true
        size="${size%%[!0-9]*}"
        if rm -rf "$old_work" 2> /dev/null; then
            left_kb=$(( left_kb + ${size:-0} ))
            left_count=$(( left_count + 1 ))
        else
            warn "could not remove $old_work, a build folder an earlier run left: delete it by hand."
        fi
    fi
done
if [[ $left_count -gt 0 ]]; then
    cleaned=true
    info "Removed $left_count build folder(s) that earlier, stopped runs left in $tmp_root ($(( left_kb / 1024 )) MB)."
fi
for old_copy in "$APPS_DIR"/Tactile.app.installing-*; do
    old_pid="${old_copy##*.installing-}"
    if [[ -z "$old_pid" || "$old_pid" == *[!0-9]* || -L "$old_copy" || ! -d "$old_copy" ]]; then
        continue   # not a copy this installer makes: left alone
    fi
    if [[ "$old_pid" != "$$" ]] && is_own_run "$old_pid"; then   # with this run's pid: an earlier, dead one
        warn "left $old_copy alone: the run that made it (pid $old_pid) is still going."
        continue
    fi
    writer="$(pgrep -f -- "${old_copy##*/}" 2> /dev/null | head -n 1 || true)"
    if [[ -n "$writer" ]]; then
        fail "$old_copy, the copy of an earlier run that was stopped, is still being written (pid $writer)." \
            "Wait a moment for it to finish, then run this again."
    fi
    if $dry_run; then
        would "remove $old_copy, the copy of an earlier run that was stopped"
    else
        rm -rf "$old_copy" || fail "Could not remove $old_copy, left by an earlier run. Move it to the Bin, then run this again."
        cleaned=true
        info "Removed $old_copy, the copy of an earlier run that was stopped."
    fi
done

step "Checking $APPS_DIR"
[[ -d "$APPS_DIR" ]] || fail "$APPS_DIR does not exist."
if [[ ! -w "$APPS_DIR" ]]; then
    fail "$APPS_DIR is not writable for $(id -un)." \
        "Installing there needs an administrator account (this script never uses sudo)." \
        "Log in as an administrator and run it again, or ask one to install Tactile."
fi
replaced=()
for left in "$APPS_DIR"/Tactile.app.replaced-*; do
    if [[ -d "$left" ]]; then replaced+=("$left"); fi
done
if [[ -L "$TARGET" ]]; then
    fail "$TARGET is a symbolic link. Remove it, then run this again."
elif [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
    fail "$TARGET is not an app. Move it away, then run this again."
elif [[ ! -e "$TARGET" || ! -f "$TARGET/Contents/Info.plist" ]]; then
    if [[ -e "$TARGET" ]]; then what="is incomplete (it has no Contents/Info.plist)"; else what="is missing"; fi
    if [[ ${#replaced[@]} -gt 0 ]]; then
        newest="${replaced[${#replaced[@]}-1]}"
        first="To put it back:"
        if [[ -e "$TARGET" ]]; then first="Move the incomplete $TARGET to the Bin, then put the old one back:"; fi
        unchanged="Then run this again. Nothing was changed."
        if $cleaned; then
            unchanged="Then run this again. Tactile itself was not changed: only what an earlier run left was removed (above)."
        fi
        fail "An earlier install was interrupted: $TARGET $what, and the old Tactile is at:" \
            "  $newest" "$first" "  mv $(printf '%q' "$newest") $(printf '%q' "$TARGET")" \
            "$unchanged"
    elif [[ -e "$TARGET" ]]; then
        fail "$TARGET $what, perhaps from an interrupted install. Move it to the Bin, then run this again."
    fi
    info "No Tactile in $APPS_DIR yet."
else
    existing_id="$(plist_value "$TARGET/Contents/Info.plist" CFBundleIdentifier)"
    if [[ "$existing_id" != "$BUNDLE_ID" ]]; then
        fail "$TARGET is not this Tactile (its identifier is '${existing_id:-missing}', not $BUNDLE_ID)." \
            "Move it away, then run this again."
    fi
    old_existed=true
    info "Installed now: $(describe_app "$TARGET")"
    for left in ${replaced[@]+"${replaced[@]}"}; do
        warn "an earlier install left $left behind. If $TARGET works, move that to the Bin."
    done
fi

step "Checking for a running Tactile"
pids=()
while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then pids+=("$pid"); fi
done < <(running_tactiles)
others=""
if [[ ${#pids[@]} -gt 0 ]]; then others_running "${pids[@]}"; fi
if [[ ${#pids[@]} -eq 0 ]]; then
    info "None is running."
elif [[ -n "$others" ]]; then
    info "Running:"
    describe_running "${pids[@]}"
    fail "Tactile is running for another user: $others. Nothing was built or installed." \
        "This run can't quit it, and can't go on while it runs. Ask them to quit it, then run this again."
elif $quit_running; then
    info "Running:"
    describe_running "${pids[@]}"
    info "With --quit-running, it will be asked to quit once the new copy has passed its checks."
else
    info "Running:"
    describe_running "${pids[@]}"
    fail "Tactile is running, so nothing was built or installed." \
        "Quit it (Quit Tactile in its menu), or run this again with --quit-running."
fi

# --- Signing ------------------------------------------------------------------------------------

work="$(mktemp -d "$tmp_root/tactile-install.XXXXXX")"
work="$(cd -P "$work" && pwd)"
case "$work/" in
    "$repo/build/"*) fail "The scratch folder $work is inside the Mac app's build/ folder. Set TMPDIR elsewhere." ;;
esac
mkdir -p "$work/tmp"

step "Choosing how to sign"
with_developer_id=false
signing_hash=""
identities="$(security find-identity -v -p codesigning 2> /dev/null)" || identities=""
if has_developer_id "$identities"; then
    certificates="$(security find-certificate -a -Z -p -c "$IDENTITY" 2> /dev/null)" || certificates=""
    signing_hash="$(newest_developer_id "$identities" "$certificates")"
fi
if [[ -n "$signing_hash" ]]; then
    info "With the Developer ID, as the downloaded releases are: $IDENTITY"
    describe_choice "$identities" "$certificates" "$signing_hash"
    info "Checking that codesign can use its key, on a scratch file. If macOS asks whether codesign may"
    info "use the key, choose Always Allow: the build signs with it again."
    cp /usr/bin/true "$work/tmp/signing-check"
    signing_status=0
    run_limited "$SIGNING_WAIT_SECONDS" codesign --force --sign "$signing_hash" --timestamp=none \
        "$work/tmp/signing-check" > "$work/signing-check.log" 2>&1 || signing_status=$?
    if [[ $signing_status -eq 124 ]]; then
        fail "codesign was still waiting after $SIGNING_WAIT_SECONDS seconds to sign with the Developer ID key, so it was stopped." \
            "macOS is probably showing a Keychain prompt for that key on this Mac's screen." \
            "Answer it with Always Allow (it asks for the login password), then run this again." \
            "Nothing was built or installed."
    elif [[ $signing_status -ne 0 ]]; then
        fail "codesign could not sign with $IDENTITY (status $signing_status). Nothing was built or installed." \
            "codesign said: $(tail -n 5 "$work/signing-check.log")" \
            "If the login keychain is locked (as over SSH), run this in Terminal on this Mac's own screen."
    fi
    info "It can. No secure timestamp is asked for: a local build is never notarized, so it signs offline."
    with_developer_id=true
else
    info "With Apple Development (team $TEAM_ID), for this build only."
    warn_signed_unlike_releases
fi
signing_settings "$signing_hash"

# --- Building -----------------------------------------------------------------------------------

step "Building Tactile (Release)"
if git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
    branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2> /dev/null || echo unknown)"
    described="$(git -C "$repo" describe --always --dirty 2> /dev/null || echo unknown)"
    info "From $repo: branch $branch, at $described."
    changes="$(git -C "$repo" status --porcelain 2> /dev/null | wc -l | tr -d ' ')"
    if [[ "$changes" == "1" ]]; then
        info "The working tree has an uncommitted change (1 file), and it is built in as it is."
    elif [[ "$changes" != "0" ]]; then
        info "The working tree has uncommitted changes ($changes files), and they are built in as they are."
    fi
else
    info "From $repo (not a git checkout)."
fi
log="$work/xcodebuild.log"
info "In the scratch folder $work (removed at the end); this takes a minute or two."
if ! TMPDIR="$work/tmp/" xcodebuild -project "$project" -scheme Tactile -configuration Release \
        -derivedDataPath "$work/DerivedData" ${signing[@]+"${signing[@]}"} build > "$log" 2>&1; then
    kept="$tmp_root/tactile-install-build.log"
    cp "$log" "$kept"
    errors="$(grep -E 'error:|BUILD FAILED' "$log" | head -n 20 || true)"
    if [[ -n "$errors" ]]; then printf '\n%s\n' "$errors" >&2; else printf '\n' >&2; tail -n 30 "$log" >&2; fi
    if grep -E 'error:' "$log" | grep -qiE 'sign|provisioning|certificate|team'; then
        if $with_developer_id; then
            fail "The Release build failed, and it looks like a signing problem. Nothing was installed." \
                "It signs with the Developer ID ($IDENTITY, SHA-1 $signing_hash), which" \
                "signed the scratch file; codesign or xcodebuild said why it could not sign the app (above)." \
                "The whole log: $kept"
        fi
        fail "The Release build failed, and it looks like a signing problem. Nothing was installed." \
            "Without a valid Developer ID in the keychain, it signs with Apple Development for team $TEAM_ID," \
            "so this Mac needs that team's Apple Development certificate (Xcode > Settings > Accounts)," \
            "or the Developer ID." \
            "The whole log: $kept"
    fi
    fail "The Release build failed. Nothing was installed." "The whole log: $kept"
fi
app="$work/DerivedData/Build/Products/Release/Tactile.app"
[[ -d "$app" ]] || fail "The build said it succeeded, but there is no app at $app."
info "Built."

step "Checking the app just built"
plist="$app/Contents/Info.plist"
built_id="$(plist_value "$plist" CFBundleIdentifier)"
[[ "$built_id" == "$BUNDLE_ID" ]] || fail "The built app's identifier is '$built_id', not $BUNDLE_ID."
built_version="$(describe_app "$app")"
info "Version: $built_version"

if ! verify_out="$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1)"; then
    fail "The built app's signature does not verify. Nothing was installed." "$verify_out"
fi
info "Signature: valid (codesign --verify --deep --strict)"
sign_info="$(codesign -dvv "$app" 2>&1)"
team="$(sed -n 's/^TeamIdentifier=//p' <<< "$sign_info")"
authority="$(sed -n 's/^Authority=//p' <<< "$sign_info" | head -n 1)"
info "Signed by: ${authority:-nobody (ad hoc)}, team ${team:-not set}"
if $with_developer_id && [[ "$authority" != "$IDENTITY" || "$team" != "$TEAM_ID" ]]; then
    fail "The built app is signed by '${authority:-nobody}' (team ${team:-not set}), not $IDENTITY. Nothing was installed."
fi
if [[ -z "$team" || "$team" == "not set" ]]; then
    warn "the app is not signed by a team, so its signature changes with each build, and macOS keeps a" \
        "stale Accessibility and Input Monitoring entry after each install: remove Tactile from both" \
        "lists in System Settings › Privacy & Security with −, and add it again with +."
fi
signed_time="$(sed -n 's/^Timestamp=//p' <<< "$sign_info")"
if [[ -n "$signed_time" ]]; then
    info "Secure timestamp: $signed_time"
else
    info "Secure timestamp: none (not needed: a local build is never notarized)"
fi
built_requirement="$(designated_requirement "$app")" || built_requirement=""
[[ -n "$built_requirement" ]] || fail "Could not read the built app's designated requirement (codesign -d -r-). Nothing was installed."
info "Designated requirement: $built_requirement"
flags="$(sed -n 's/^CodeDirectory .*flags=\(0x[0-9a-f]*([^)]*)\).*/\1/p' <<< "$sign_info")"
[[ "$flags" == *runtime* ]] || fail "The built app does not have the hardened runtime (its flags: ${flags:-none})." \
    "ENABLE_HARDENED_RUNTIME must stay YES in Tactile.xcodeproj."
info "Hardened runtime: yes ($flags)"
entitlements="$work/entitlements.plist"
if ! codesign -d --entitlements - --xml "$app" > "$entitlements" 2> /dev/null; then
    fail "Could not read the built app's entitlements, so it can't be shown not to be sandboxed. Nothing was installed."
fi
sandbox=""
if [[ -s "$entitlements" ]]; then
    plutil -lint -s "$entitlements" > /dev/null 2>&1 || \
        fail "Could not read the built app's entitlements (they are not a valid property list). Nothing was installed."
    sandbox="$(plist_value "$entitlements" com.apple.security.app-sandbox)"
fi
if [[ "$sandbox" == "true" ]]; then
    fail "The built app is sandboxed (com.apple.security.app-sandbox). Nothing was installed." \
        "Tactile reads touchscreens and posts events, which a sandboxed app can't. Check Tactile/Tactile.entitlements."
fi
info "Sandbox: no"
built_hash="$(cdhash "$app")" || built_hash=""
[[ -n "$built_hash" ]] || fail "Could not read the built app's code directory hash. Nothing was installed."

if $old_existed; then
    step "Comparing its signature with the Tactile in $APPS_DIR"
    compare_with_installed "$TARGET" "$app"
    if $signing_changed; then
        if $dry_run; then
            would "install it all the same"
        else
            info "The install goes ahead all the same."
        fi
    fi
fi

step "Making sure no Tactile was started meanwhile"
pids=()
while IFS= read -r pid; do
    if [[ -n "$pid" ]]; then pids+=("$pid"); fi
done < <(running_tactiles)
others=""
if [[ ${#pids[@]} -gt 0 ]]; then others_running "${pids[@]}"; fi
if [[ ${#pids[@]} -eq 0 ]]; then
    info "None is running."
elif [[ -n "$others" ]]; then
    describe_running "${pids[@]}"
    fail "Tactile was started for another user while it was being built: $others. Nothing was installed." \
        "This run can't quit it, and can't go on while it runs. Ask them to quit it, then run this again."
elif $quit_running; then
    describe_running "${pids[@]}"
    info "Still running: it will be asked to quit as said."
else
    describe_running "${pids[@]}"
    fail "Tactile was started while it was being built, so nothing was installed." \
        "Quit it (Quit Tactile in its menu), or run this again with --quit-running."
fi

# --- Installing ---------------------------------------------------------------------------------

step "Installing $TARGET"
staging="$APPS_DIR/Tactile.app.installing-$$"
if $dry_run; then
    would "copy the app just built to $staging with ditto, and check it there: codesign --verify --deep --strict, its identifier and version, and the same signature (CDHash $built_hash)"
    if [[ ${#pids[@]} -gt 0 ]]; then
        would "then ask the running Tactile to quit (SIGTERM), wait up to $QUIT_WAIT_SECONDS seconds, and stop if it is still running"
    fi
    if $old_existed; then
        would "then rename $TARGET to $APPS_DIR/Tactile.app.replaced-<time>-<pid>, rename the checked copy to $TARGET, and remove the old one"
    else
        would "then rename the checked copy to $TARGET"
    fi
    info "On a failure or an interruption before the new copy is in place, it would remove the copy, and"
    info "rename the old Tactile back if it had been renamed aside."
    info "Nothing in $APPS_DIR was changed."
else
    replace_state="copying"
    if ! ditto "$app" "$staging"; then
        stop_install "Copying the new Tactile into $APPS_DIR failed."
    fi
    replace_state="verifying"
    if ! verify_out="$(codesign --verify --deep --strict --verbose=2 "$staging" 2>&1)"; then
        stop_install "The copy in $APPS_DIR does not verify: $verify_out"
    fi
    copy_id="$(plist_value "$staging/Contents/Info.plist" CFBundleIdentifier)"
    copy_version="$(describe_app "$staging")"
    copy_hash="$(cdhash "$staging")" || copy_hash=""
    if [[ "$copy_id" != "$BUNDLE_ID" || "$copy_version" != "$built_version" || "$copy_hash" != "$built_hash" ]]; then
        stop_install "The copy in $APPS_DIR is not the app just built ($copy_id, $copy_version, CDHash ${copy_hash:-none})."
    fi
    info "Copied as $staging, and checked: $copy_version, signature valid, CDHash $copy_hash"

    pids=()
    while IFS= read -r pid; do
        if [[ -n "$pid" ]]; then pids+=("$pid"); fi
    done < <(running_tactiles)
    if [[ ${#pids[@]} -gt 0 ]]; then
        describe_running "${pids[@]}"
        others_running "${pids[@]}"
        if [[ -n "$others" ]]; then
            stop_unchanged "Tactile was started for another user during the install: $others. This run can't quit it, and can't go on while it runs."
        fi
        if ! $quit_running; then
            stop_install "Tactile was started during the install, so it was not finished."
        fi
        info "Asking it to quit..."
        quit_pids=("${pids[@]}")
        quit_asked=true
        for pid in "${pids[@]}"; do
            kill -TERM "$pid" 2> /dev/null || true
        done
        still=()
        for (( tick = 0; tick < QUIT_WAIT_SECONDS * 2; tick++ )); do
            still=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2> /dev/null; then still+=("$pid"); fi
            done
            if [[ ${#still[@]} -eq 0 ]]; then break; fi
            sleep 0.5
        done
        if [[ ${#still[@]} -gt 0 ]]; then
            stop_install "Tactile (pid ${still[*]}) is still running $QUIT_WAIT_SECONDS seconds after being asked to quit; it was not forced. Quit it from its menu, then run this again."
        fi
        quit_done=true
        info "It has quit."
    fi

    replaced_name="$APPS_DIR/Tactile.app.replaced-$(date +%Y%m%d-%H%M%S)-$$"   # named first: nothing
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then                                  # runs between the check and the rename
        # Only the Tactile checked at the start is renamed aside: checked again now, as it may have
        # changed while this ran. Anything else is left as it is.
        if ! $old_existed || [[ -L "$TARGET" || ! -d "$TARGET" ]] ||
            [[ "$(plist_value "$TARGET/Contents/Info.plist" CFBundleIdentifier)" != "$BUNDLE_ID" ]]; then
            stop_unchanged "$TARGET changed while this ran: it is not the Tactile checked at the start, so it was left as it is."
        fi
        aside="$replaced_name"
        replace_state="moving-old"
        mv "$TARGET" "$aside" || stop_install "Could not rename the old $TARGET aside."
        # What was renamed must be the Tactile just checked. If something was put there in that
        # instant, it is renamed straight back and left as it is.
        if [[ -L "$aside" || ! -d "$aside" ]] ||
            [[ "$(plist_value "$aside/Contents/Info.plist" CFBundleIdentifier)" != "$BUNDLE_ID" ]]; then
            if [[ ! -e "$TARGET" && ! -L "$TARGET" ]] && mv "$aside" "$TARGET"; then
                aside=""
                replace_state="verifying"
                stop_unchanged "$TARGET changed while this ran: it is not the Tactile checked at the start, so it was left as it is."
            fi
            stop_install "$TARGET changed while this ran, and what was there could not be renamed back."
        fi
    fi
    replace_state="moving-new"
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        stop_install "Something appeared at $TARGET during the install."
    fi
    mv "$staging" "$TARGET" || stop_install "Could not rename the checked copy to $TARGET."
    replace_state="placed"
    # Before the old copy is removed: the checked copy must have the real name, not have gone inside
    # something that appeared there in the meantime.
    if [[ -e "$TARGET/${staging##*/}" || -L "$TARGET/${staging##*/}" ]]; then
        stop_install "Something appeared at $TARGET during the install, and the checked copy went inside it."
    fi
    # The old copy is removed only once what has the name is confirmed to carry the checked copy's
    # code-directory hash; one that can't be read is not a confirmation.
    if ! confirmed_at_target; then
        placed_hash="$(sed -n 's/^CDHash=//p' "$work/confirm.txt" 2> /dev/null | head -n 1)" || placed_hash=""
        replace_state="unconfirmed"
        stop_install "What is now at $TARGET is not confirmed to be the checked copy (CDHash ${placed_hash:-unreadable})."
    fi
    replace_state="installed"
    info "Renamed into place: $TARGET"
    if [[ -n "$aside" ]]; then
        if rm -rf "$aside"; then
            info "Removed the old copy."
        else
            warn "the new Tactile is installed, but the old copy could not be removed: $aside. Move it to the Bin in Finder."
        fi
        aside=""
    fi
fi

# --- What next ----------------------------------------------------------------------------------

if $dry_run; then
    real_run="Tools/install.sh"
    if $quit_running; then real_run="$real_run --quit-running"; fi
    step "Dry run finished: $built_version would be installed as $TARGET"
    if [[ ${#pids[@]} -gt 0 ]]; then
        printf '\nTactile would be quit for the install and not started again.\n'
    fi
    printf '\nAfter a real run (%s):\n' "$real_run"
else
    step "Installed: $built_version as $TARGET"
    if $quit_done; then
        printf '\nTactile was quit for the install and has not been started again.\n'
    fi
    printf '\nNext:\n'
fi
cat <<'EOF'
  1. Open Tactile from Applications (in Finder, or: open /Applications/Tactile.app). It lives in the
     menu bar; there is no Dock icon.
  2. If macOS asks for Accessibility access when you press Open Accessibility Settings… in
     Tactile's Settings, allow Tactile there.
EOF
if $signing_changed; then
    printf '%s\n' "     It was signed differently before: if Tactile says Accessibility access is missing while" \
        "     it is switched on there, remove Tactile from that list and from Input Monitoring with −," \
        "     and add it again with +."
fi
if $old_existed; then
    printf '%s\n' "  3. Check that Launch at login is still on, in Tactile's Settings under General."
else
    printf '%s\n' "  3. In Tactile's Settings, under General, switch on Launch at login. It works only for the copy" \
        "     in Applications."
fi
finished=true
