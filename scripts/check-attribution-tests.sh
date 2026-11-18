#!/usr/bin/env bash
# Tests for scripts/check-attribution.sh and the git hooks in .githooks.
#
#   scripts/check-attribution-tests.sh
#
# Everything runs in a temporary folder, which is removed afterwards. The
# user's own git configuration is kept out, so the results are the same on
# every machine. Exits non-zero if any test fails.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
check="$here/check-attribution.sh"
hooks="$root/.githooks"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-attribution-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Keep the user's git configuration (hooks, signing, comment character) out.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Test Person' GIT_AUTHOR_EMAIL='test@example.com'
export GIT_COMMITTER_NAME='Test Person' GIT_COMMITTER_EMAIL='test@example.com'
cd "$work"

passed=0
failed=0
ok() { passed=$((passed + 1)); }
not_ok() {
  failed=$((failed + 1))
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -s $work/out ]]; then sed 's/^/      /' "$work/out" >&2; fi
}

# run <args...>: runs the checker, keeping its output in $work/out and its
# exit status in $status.
status=0
run() {
  status=0
  "$check" "$@" >"$work/out" 2>&1 || status=$?
}

# refused <name> <text> [line]: the text (printf %b escapes allowed) is
# refused in both text modes, and the report quotes the line that matched:
# the given one, or else the text's last non-empty line.
refused() {
  local name=$1 text=$2 line=${3:-} mode
  printf '%b' "$text" >"$work/text"
  if [[ -z $line ]]; then line=$(grep -v '^[[:space:]]*$' "$work/text" | tail -n 1 | tr -d '\r'); fi
  for mode in --message-file --text-file; do
    run "$mode" "$work/text"
    if [[ $status -ne 1 ]]; then
      not_ok "$name ($mode): expected exit 1, got $status"
    elif ! grep -qF -- "$line" "$work/out"; then
      not_ok "$name ($mode): the report doesn't quote \"$line\""
    else
      ok
    fi
  done
}

# allowed <name> <text> [mode]: the text passes the given mode, or both text
# modes if none is given.
allowed() {
  local name=$1 text=$2 modes mode
  modes=${3:-'--message-file --text-file'}
  printf '%b' "$text" >"$work/text"
  for mode in $modes; do
    run "$mode" "$work/text"
    if [[ $status -ne 0 ]]; then not_ok "$name ($mode): expected exit 0, got $status"; else ok; fi
  done
}

# expect <name> <status> [text the output must contain]...: checks the last run.
expect() {
  local name=$1 want=$2 needle
  shift 2
  if [[ $status -ne $want ]]; then
    not_ok "$name: expected exit $want, got $status"
    return
  fi
  for needle in "$@"; do
    if ! grep -qF -- "$needle" "$work/out"; then
      not_ok "$name: the output doesn't contain \"$needle\""
      return
    fi
  done
  ok
}

# ---------------------------------------------------------------------------
# Refused: a Co-authored-by trailer that names an AI tool, one per tool.
# ---------------------------------------------------------------------------
for tool in 'Claude' 'Claude Opus 5.5' 'Anthropic' 'Copilot' 'GitHub Copilot' \
  'OpenAI' 'ChatGPT' 'GPT' 'GPT-5' 'Codex' 'Cursor' 'Gemini' 'Google Gemini' \
  'Devin' 'Aider' 'Windsurf' 'Cody' 'Sourcegraph Cody' 'Amazon Q' 'Codeium' \
  'Tabnine' 'Jules' 'Grok'; do
  refused "co-author trailer naming $tool" "Fix the edge swipe\n\nCo-Authored-By: $tool <helper@example.com>\n"
done

# Refused: co-author trailers as the tools actually write them.
refused 'Claude Code co-author trailer' \
  'Fix it\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n'
refused 'co-author trailer with an anthropic.com address' \
  'Fix it\n\nCo-authored-by: Helper <noreply@anthropic.com>\n'
refused 'Copilot co-author trailer' \
  'Fix it\n\nCo-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>\n'
refused 'Cursor co-author trailer' \
  'Fix it\n\nCo-authored-by: Cursor Agent <cursoragent@cursor.com>\n'
refused 'Jules co-author trailer' \
  'Fix it\n\nCo-authored-by: google-labs-jules[bot] <161369871+google-labs-jules[bot]@users.noreply.github.com>\n'
refused 'Devin co-author trailer' \
  'Fix it\n\nCo-authored-by: devin-ai-integration[bot] <158243242+devin-ai-integration[bot]@users.noreply.github.com>\n'
refused 'aider co-author trailer' \
  'Fix it\n\nCo-authored-by: aider (gpt-4o) <noreply@aider.chat>\n'
refused 'co-author trailer in lower case with no space' \
  'Fix it\n\nco-authored-by:claude <x@example.com>\n'
refused 'co-author trailer in capitals, indented' \
  'Fix it\n\n   CO-AUTHORED-BY :  ChatGPT\n'
refused 'co-author trailer with a space for a hyphen' \
  'Fix it\n\nCo-authored by: Gemini\n'
refused 'another -by trailer naming an AI tool' \
  'Fix it\n\nSigned-off-by: Claude <noreply@anthropic.com>\n'
refused 'an Assisted-by trailer naming an AI tool' \
  'Fix it\n\nAssisted-by: GitHub Copilot\n'
refused 'a co-author line in a markdown list' \
  'Add the menu\n\n- Co-authored-by: Claude <noreply@anthropic.com>\n'
refused 'a co-author line in bold' \
  'Add the menu\n\n**Co-authored-by:** Windsurf\n'
refused 'a co-author mention in a title' \
  'Add the menu (Co-authored-by: Copilot)\n\nThe menu opens on a long press.\n' \
  'Add the menu (Co-authored-by: Copilot)'

# Refused: "Generated with" followed by an AI tool.
refused 'generated with ChatGPT' 'Add the menu\n\nGenerated with ChatGPT\n'
refused 'generated with GitHub Copilot' 'Add the menu\n\ngenerated with GitHub Copilot\n'
refused 'generated with a linked tool' 'Add the menu\n\nGenerated with [Gemini](https://gemini.google.com)\n'
refused 'generated with a tool in bold' 'Add the menu\n\nGenerated with **Cursor**\n'
refused 'generated with [Claude Code]' 'Add the menu\n\nGenerated with [Claude Code](https://claude.com/claude-code)\n'

# Refused: the robot emoji followed by "Generated".
refused 'robot emoji, then Generated' 'Add the menu\n\n\xf0\x9f\xa4\x96 Generated by the release tool\n'
refused 'robot emoji, then Generated, no space' 'Add the menu\n\n\xf0\x9f\xa4\x96Generated\n'

# Refused: links to Claude Code.
refused 'a claude.ai/code link' 'Add the menu\n\nhttps://claude.ai/code/session_01AbCdEf\n'
refused 'a claude.com/claude-code link' 'Add the menu\n\nSee https://www.claude.com/claude-code for details\n'

# Refused: a Claude-Session trailer.
refused 'a Claude-Session trailer' 'Add the menu\n\nClaude-Session: 4f2a9c1e-77b0-4d2e-9d1a-0c5e6b3a8f21\n'

# Refused: the phrase "Claude Code".
refused 'the phrase Claude Code' 'Add the menu\n\nWritten in Claude Code over an afternoon.\n'
refused 'the phrase claude-code' 'Add the menu\n\nwritten with claude-code\n'

# Refused: Windows line endings, as a pull request body often has.
refused 'CRLF line endings' 'Add the menu\r\n\r\nGenerated with ChatGPT\r\n' 'Generated with ChatGPT'

# Refused: every offending line is quoted, with its line number.
printf 'Add the menu\n\nThe menu opens on a long press.\n\nGenerated with Codex\nCo-authored-by: Codex <codex@openai.com>\n' >"$work/many"
run --text-file "$work/many"
expect 'two offending lines are both quoted' 1 'line 5: Generated with Codex' 'line 6: Co-authored-by: Codex <codex@openai.com>'

# ---------------------------------------------------------------------------
# Allowed.
# ---------------------------------------------------------------------------
allowed 'a human co-author' 'Fix the edge swipe\n\nCo-authored-by: Jane Doe <jane@example.com>\n'
allowed 'human co-author and sign-off trailers' \
  'Fix the edge swipe\n\nCo-authored-by: Sam Doe <sam@example.com>\nSigned-off-by: Jane Doe <jane@example.com>\n'
allowed 'the word agent' \
  'Let agents pair with Tactile\n\nThe agent now asks before it moves the pointer. Agents\nsee the same state as the menu. User agent strings are logged.\n'
allowed 'Claude as a first name in a sentence' \
  'Fix the left edge\n\nClaude reported the jitter on the left edge, and Claude Monet\nwould have liked the new colours.\n'
allowed 'the Tactile domain' \
  'Point the updater at the site\n\nTactile asks https://tactilemac.com/api/mac/latest for updates.\nSee tactilemac.com.\n'
allowed 'cursor and generated in ordinary Tactile sentences' \
  'Keep the cursor still\n\nEvents generated by cursor warping are ignored, and the cursor\nstays where it was. The codec path is unchanged.\n'
allowed 'generated with something that is not an AI tool' \
  'Generated with care\n\nThe gesture table is generated with a script.\n'

# Comment lines are ignored in a commit message, as git ignores them, but
# not in pull request text.
comments='Fix the edge swipe\n\n# Co-Authored-By: Claude <noreply@anthropic.com>\n# Please enter the commit message for your changes.\n#\tnew file:   docs/claude-code-notes.md\n'
allowed 'comment lines in a commit message' "$comments" --message-file
printf '%b' "$comments" >"$work/comments"
run --text-file "$work/comments"
expect 'comment lines are not ignored in pull request text' 1 'Co-Authored-By: Claude'

# Everything below the scissors line (git commit -v) is ignored.
allowed 'the diff below the scissors line' \
  'Fix the edge swipe\n\n# ------------------------ >8 ------------------------\n# Do not modify or remove the line above.\ndiff --git a/README.md b/README.md\n+Generated with [Claude Code](https://claude.com/claude-code)\n' \
  --message-file

# ---------------------------------------------------------------------------
# Usage errors exit 2.
# ---------------------------------------------------------------------------
run
expect 'no arguments' 2 'usage'
run --nonsense x
expect 'an unknown mode' 2 'usage'
run --text-file "$work/does-not-exist"
expect 'a missing file' 2 'does-not-exist'

# ---------------------------------------------------------------------------
# Range mode, against a throwaway repository.
# ---------------------------------------------------------------------------
repo="$work/repo"
git init -q -b main "$repo"
cd "$repo"
git config core.hooksPath "$work/no-hooks"
git commit -q --allow-empty -m 'Start the project'
start=$(git rev-parse HEAD)
git commit -q --allow-empty -m 'Add the gesture table' -m 'Co-authored-by: Jane Doe <jane@example.com>'
clean_tip=$(git rev-parse HEAD)

git switch -q -c feature
git commit -q --allow-empty -m 'Add the frobnicator' -m 'Co-Authored-By: Claude <noreply@anthropic.com>'
bad=$(git rev-parse --short HEAD)
git commit -q --allow-empty -m 'Tidy the frobnicator' -m 'Generated with Copilot'
bad2=$(git rev-parse --short HEAD)

git switch -q main
git switch -q -c side
git commit -q --allow-empty -m 'Add the side panel'
git switch -q main
git merge -q --no-ff -m $'Merge the side panel\n\nClaude-Session: 1234' side
bad_merge=$(git rev-parse --short HEAD)
git switch -q -c side2 "$clean_tip"
git commit -q --allow-empty -m 'Add the second panel'
git switch -q main
git merge -q --no-ff -m 'Merge the second panel' side2
clean_merge=$(git rev-parse HEAD)

run --range "$start..$clean_tip"
expect 'range: clean commits pass' 0 'Checked 1 commit;'
run --range "$clean_tip..feature"
expect 'range: every offending commit is named, with its subject and line' 1 \
  "$bad" 'Add the frobnicator' 'Co-Authored-By: Claude <noreply@anthropic.com>' \
  "$bad2" 'Tidy the frobnicator' 'Generated with Copilot'
run --range "$clean_tip..$bad_merge"
expect 'range: a merge commit is checked' 1 "$bad_merge" 'Merge the side panel' 'Claude-Session: 1234'
run --range "$bad_merge..$clean_merge"
expect 'range: a clean merge commit passes' 0 'Checked 2 commits;'
run --range "main..main"
expect 'range: an empty range passes' 0 'No commits'
run --range "$start"
expect 'range: a single revision checks its whole history' 0 'Checked 1 commit;'
run --range "no-such-branch..main"
expect 'range: an unknown revision is an error' 2 'no-such-branch'
run --range "main...feature"
expect 'range: a symmetric range is a usage error' 2 'usage'

# ---------------------------------------------------------------------------
# The hooks, end to end.
# ---------------------------------------------------------------------------
for hook in commit-msg pre-push; do
  if [[ -x $hooks/$hook ]]; then ok; else not_ok "$hooks/$hook is missing or not executable"; fi
done

hooked="$work/hooked"
remote="$work/remote.git"
git init -q --bare "$remote"
git init -q -b main "$hooked"
cd "$hooked"
git config core.hooksPath "$hooks"
git remote add origin "$remote"

# commit-msg
status=0
git commit -q --allow-empty -m 'Start the project' >"$work/out" 2>&1 || status=$?
expect 'commit-msg: a clean commit is made' 0
before=$(git rev-parse HEAD)
status=0
git commit -q --allow-empty -m 'Add the menu' -m 'Co-Authored-By: Claude <noreply@anthropic.com>' >"$work/out" 2>&1 || status=$?
if [[ $status -ne 0 && $(git rev-parse HEAD) == "$before" ]] && grep -qF 'Co-Authored-By: Claude' "$work/out"; then
  ok
else
  not_ok 'commit-msg: a commit that credits an AI tool is refused'
fi
printf 'Add the menu\n\n# Co-Authored-By: Claude <noreply@anthropic.com>\n' >"$work/editmsg"
status=0
git commit -q --allow-empty --cleanup=strip -F "$work/editmsg" >"$work/out" 2>&1 || status=$?
expect 'commit-msg: comment lines that git strips are ignored' 0
if git log -1 --format=%B | grep -qi 'claude'; then not_ok 'commit-msg: git kept the comment line'; else ok; fi

# pre-push: the first push of a branch to an empty remote.
status=0
git push -q origin main >"$work/out" 2>&1 || status=$?
expect 'pre-push: a clean first push goes through' 0

# pre-push: a new branch carrying a commit made with --no-verify.
git switch -q -c topic
git commit -q --no-verify --allow-empty -m 'Add the panel' -m 'Generated with [Claude Code](https://claude.com/claude-code)'
status=0
git push -q origin topic >"$work/out" 2>&1 || status=$?
expect 'pre-push: a new branch with an offending commit is refused' 1 'Add the panel' 'Generated with [Claude Code]'
if git --git-dir="$remote" rev-parse --verify -q refs/heads/topic >/dev/null; then
  not_ok 'pre-push: the refused branch reached the remote'
else
  ok
fi

# pre-push: the same branch, reworded, goes through.
git commit -q --no-verify --amend --allow-empty -m 'Add the panel'
status=0
git push -q origin topic >"$work/out" 2>&1 || status=$?
expect 'pre-push: the reworded branch goes through' 0
pushed=$(git rev-parse HEAD)

# pre-push: an update to a branch the remote already has.
git commit -q --no-verify --allow-empty -m 'Move the panel' -m 'Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>'
status=0
git push -q origin topic >"$work/out" 2>&1 || status=$?
expect 'pre-push: an update with an offending commit is refused' 1 'Move the panel'
if [[ $(git --git-dir="$remote" rev-parse refs/heads/topic) == "$pushed" ]]; then ok; else not_ok 'pre-push: the refused update reached the remote'; fi

# pre-push: a force push of rewritten history is checked too.
git reset -q --hard "$pushed"
git commit -q --no-verify --amend --allow-empty -m 'Add the panel again' -m 'Claude-Session: abc'
status=0
git push -q --force origin topic >"$work/out" 2>&1 || status=$?
expect 'pre-push: a force push with an offending commit is refused' 1 'Add the panel again'

# pre-push: deleting a branch is not checked.
status=0
git push -q origin :topic >"$work/out" 2>&1 || status=$?
expect 'pre-push: deleting a branch goes through' 0

# ---------------------------------------------------------------------------
# Lint every script with shellcheck, when it is installed.
# ---------------------------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  status=0
  shellcheck "$check" "$here/check-attribution-tests.sh" "$hooks/commit-msg" "$hooks/pre-push" >"$work/out" 2>&1 || status=$?
  expect 'shellcheck is clean' 0
else
  printf 'shellcheck is not installed; skipped.\n'
fi

printf '%d passed, %d failed.\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
