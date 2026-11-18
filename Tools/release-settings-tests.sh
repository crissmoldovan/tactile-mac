#!/usr/bin/env bash
# Tests the two settings release.sh takes from the environment:
#   - TACTILE_RELEASE_REPO, the GitHub repository a release is published to: owner/name, by default
#     crissmoldovan/tactile-mac; anything else is refused before anything is built;
#   - TACTILE_BUILD_OFFSET, a whole number added to git rev-list --count HEAD to make the build
#     number, by default 500, so this repository's builds go on above the last build released
#     before it (471);
# the two helpers that refuse a build number not above the newest published release's: the
# newest mac-v<version> tag, by version, and the comparison; and the one that refuses a build not
# above the build the website serves now, read from stand-in answers (no network).
# It sources release.sh in a new bash, which then only defines its functions: nothing is built,
# signed or published, and nothing outside this process is read or changed.
# Usage: Tools/release-settings-tests.sh. Exit status 0 when every check passes.
set -euo pipefail

tools="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

in_release() {  # in_release <command...>: runs it in a new bash that has sourced release.sh
    bash -c 'source "$1" || exit 99; shift; "$@"' in_release "$tools/release.sh" "$@"
}

# shellcheck disable=SC2016  # expanded by eval in the bash that sourced release.sh
check "sourcing release.sh runs none of it" \
    in_release eval '[[ -z "${dry_run+set}${notes_file+set}${work+set}" && -z "$(trap -p EXIT)" ]]'

# --- TACTILE_RELEASE_REPO -----------------------------------------------------------------------

check "no repository given: crissmoldovan/tactile-mac" equal "$(in_release release_repo "")" "crissmoldovan/tactile-mac"
# shellcheck disable=SC2016  # expanded by eval in the bash that sourced release.sh
check "the default is named once, as DEFAULT_RELEASE_REPO" \
    equal "$(in_release eval 'printf %s "$DEFAULT_RELEASE_REPO"')" "crissmoldovan/tactile-mac"
for repo in crissmoldovan/tactile-mac crissmoldovan/tactile Some-Owner/some.repo_name-2 a/b; do
    check "owner/name is taken as it is: $repo" equal "$(in_release release_repo "$repo")" "$repo"
done
# shellcheck disable=SC2016  # '$(x)' is a value to refuse, not to expand
for repo in tactile crissmoldovan/ /tactile crissmoldovan/tactile/extra "crissmoldovan/tactile mac" \
        "crissmoldovan/tactile;rm" 'crissmoldovan/$(x)' crissmoldovan/.. crissmoldovan/. -owner/repo \
        https://github.com/crissmoldovan/tactile "owner/name
x"; do
    check "refused: $(printf '%q' "$repo")" not in_release release_repo "$repo"
done

# --- TACTILE_BUILD_OFFSET -----------------------------------------------------------------------

check "no offset: 500 is added" equal "$(in_release build_number 12 "")" "512"
check "this repository's first commit is build 501" equal "$(in_release build_number 1 "")" "501"
check "... above 471, the last build released before it" test "$(in_release build_number 1 "")" -gt 471
# shellcheck disable=SC2016  # expanded by eval in the bash that sourced release.sh
check "the default offset is named once, as DEFAULT_BUILD_OFFSET" \
    equal "$(in_release eval 'printf %s "$DEFAULT_BUILD_OFFSET"')" "500"
check "offset 0: the commit count is the build" equal "$(in_release build_number 12 0)" "12"
check "offset 1000: added to the count" equal "$(in_release build_number 12 1000)" "1012"
check "a short history goes on above 471" test "$(in_release build_number 1 471)" -gt 471
for offset in -5 1.5 abc 10a " 10" 007 99999999999 "1 2"; do
    check "offset refused: $(printf '%q' "$offset")" not in_release build_number 12 "$offset"
done
check "a count that isn't a number is refused" not in_release build_number "" 0

# --- The newest release already published ---------------------------------------------------------

tags="$(printf '%s\n' mac-v0.6.0 mac-v0.6.2 mac-v0.6.1 mac-v0.10.0 mac-v0.9.9 web-v1.0.0 v2.0.0 mac-v1.0 mac-v01.2.3 "")"
check "the newest is chosen by version, not as text" equal "$(in_release newest_mac_tag "$tags")" "mac-v0.10.0"
check "other tags are left out" equal "$(in_release newest_mac_tag "$(printf '%s\n' mac-v0.6.2 web-v9.0.0 mac-v9)")" "mac-v0.6.2"
check "no release: nothing" equal "$(in_release newest_mac_tag "")" ""
check "releases, but none of Tactile: nothing" equal "$(in_release newest_mac_tag "$(printf '%s\n' web-v1.0.0 v2.0.0)")" ""

check "a build above the published one goes" in_release build_is_newer 1003 471
check "the same build is refused" not in_release build_is_newer 471 471
check "a lower build is refused" not in_release build_is_newer 3 471
check "a published build that isn't a number is refused" not in_release build_is_newer 472 ""
check "... nor one with a sign" not in_release build_is_newer 472 -1

# --- The build the website serves now -------------------------------------------------------------
# Stand-ins for the answer of https://tactilemac.com/api/mac/update; nothing is fetched.

served_answer='{"version":"0.6.2","build":471,"minimumSystemVersion":"14.0","publishedAt":"2026-11-17T21:04:11Z",
"notes":"One paragraph.","archive":{"url":"https://tactilemac.com/api/mac/archive/0.6.2","size":7340032,
"sha256":"00","signature":"AA==","keyId":"k1"}}'
served() {  # served <build> <answer> <expected status> <expected output>
    local out status=0
    out="$(in_release above_served_build "$1" "$2")" || status=$?
    [[ "$status" == "$3" && "$out" == "$4" ]]
}
check "a build above the site's goes, and says the site's" served 501 "$served_answer" 0 471
check "the site's own build is refused" served 471 "$served_answer" 1 471
check "a build below the site's is refused" served 2 "$served_answer" 1 471
check "a fresh repository's build without the offset is refused" served 1 "$served_answer" 1 471
check "no answer (offline, or curl failed) can't be read" served 501 "" 2 ""
check "the site's error can't be read" served 501 '{"error":"No release with all its files yet."}' 2 ""
check "an answer that isn't JSON can't be read" served 501 '<html>Not found</html>' 2 ""
check "a build written as text can't be read" served 501 '{"build":"471"}' 2 ""
check "a build that isn't whole can't be read" served 501 '{"build":471.5}' 2 ""
check "a negative build can't be read" served 501 '{"build":-1}' 2 ""
check "a build that is no number at all can't be read" served 501 '{"build":true}' 2 ""

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
