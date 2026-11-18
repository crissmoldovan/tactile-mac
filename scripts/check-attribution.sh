#!/usr/bin/env bash
# Refuses commit messages and pull request text that credit an AI tool.
#
#   check-attribution.sh --message-file <path>   a commit message being written
#                                                (the commit-msg hook); lines
#                                                git treats as comments are
#                                                ignored, as git ignores them
#   check-attribution.sh --range <base>..<head>  every commit in the range,
#                                                merge commits included (the
#                                                pre-push hook and CI); a lone
#                                                <head> checks all its history
#   check-attribution.sh --text-file <path>      a pull request's title and body
#
# Exits 0 when nothing credits an AI tool, 1 when something does (each
# offending commit and line is named), and 2 on a usage or git error.
# See CONTRIBUTING.md.

set -euo pipefail

# ---------------------------------------------------------------------------
# The AI tools. Each entry is an extended regular expression, matched without
# regard to case and as a whole word (no letter directly before or after it).
# To add a tool, add a line here and a case in check-attribution-tests.sh.
# ---------------------------------------------------------------------------
AI_TOOLS=(
  'claude'
  'anthropic'
  '(github[[:space:]]+)?copilot'
  'open[[:space:]_-]?ai'
  'chatgpt'
  'gpt'
  'codex'
  'cursor'
  '(google[[:space:]]+)?gemini'
  'devin'
  'aider'
  'windsurf'
  '(sourcegraph[[:space:]]+)?cody'
  'amazon[[:space:]_-]*q'
  'codeium'
  'tabnine'
  'jules'
  'grok'
)

# ---------------------------------------------------------------------------
# What counts as crediting one of them: one extended regular expression per
# line of text, matched without regard to case.
# ---------------------------------------------------------------------------
tools="($(IFS='|' && printf '%s' "${AI_TOOLS[*]}"))"
before='(^|[^[:alpha:]])'
after='([^[:alpha:]]|$)'
# The rest of a trailer line after its colon, up to a tool named in it.
names=":(.*[^[:alpha:]])?${tools}${after}"
PATTERNS=(
  # A Co-authored-by trailer naming an AI tool or its address, anywhere in a
  # line (including "Co-authored by:" and other spellings, in markdown, or
  # in a pull request title).
  "${before}co[[:space:]_-]*authored[[:space:]_-]*by[[:space:]]*${names}"
  # Any other "...-by:" trailer naming one: Signed-off-by, Assisted-by.
  "^[^[:alnum:]]*[[:alpha:]][[:alpha:]-]*-by[[:space:]]*${names}"
  # "Generated with" an AI tool, also as a link or in bold: [Claude Code](...).
  "generated[[:space:]]+with[[:space:]]+[^[:alnum:][:space:]]{0,3}${tools}${after}"
  # The robot emoji, then "Generated".
  $'\xf0\x9f\xa4\x96''[^[:alnum:]]*generated'
  # Links to Claude Code.
  'claude\.com/claude-code'
  'claude\.ai/code'
  # A Claude-Session trailer.
  '^[^[:alnum:]]*claude[[:space:]_-]*session[[:space:]]*:'
  # The phrase "Claude Code" (or claude-code).
  "${before}claude[[:space:]_-]*code${after}"
)

GREP_ARGS=()
for pattern in "${PATTERNS[@]}"; do GREP_ARGS+=(-e "$pattern"); done

me=$(basename "$0")

usage() {
  {
    printf '%s\n' "$1"
    printf 'usage: %s --message-file <path>\n' "$me"
    printf '       %s --range <base>..<head>\n' "$me"
    printf '       %s --text-file <path>\n' "$me"
  } >&2
  exit 2
}

fail() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 2
}

# Reads text on stdin and prints "<line number>:<line>" for each line that
# credits an AI tool.
find_credits() {
  local status=0
  tr -d '\r' | LC_ALL=C grep -n -i -E "${GREP_ARGS[@]}" || status=$?
  if [[ $status -gt 1 ]]; then fail 'grep failed'; fi
}

# report <what> <matches>: names what was checked and quotes each line.
report() {
  local match
  printf '%s credits an AI tool:\n' "$1" >&2
  while IFS= read -r match; do
    printf '  line %s: %s\n' "${match%%:*}" "${match#*:}" >&2
  done <<<"$2"
}

advice() {
  {
    printf '\nThis repository does not accept commits or pull requests that say an AI tool\n'
    printf 'wrote or co-wrote them. Remove the lines above and try again: for the last\n'
    printf 'commit, git commit --amend; for older ones, git rebase -i and "reword"; for a\n'
    printf 'pull request, edit its title or description. See CONTRIBUTING.md.\n'
  } >&2
}

# The commit message without the lines git drops: comment lines (kept as
# blank lines, so line numbers still match the file) and everything from the
# scissors line of "git commit -v" down.
commit_message() {
  local comment line scissors
  comment=$(git config --get core.commentString 2>/dev/null) ||
    comment=$(git config --get core.commentChar 2>/dev/null) || comment='#'
  if [[ -z $comment || $comment == auto ]]; then comment='#'; fi
  scissors="$comment ------------------------ >8 ------------------------"
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line == "$scissors" ]]; then break; fi
    if [[ $line == "$comment"* ]]; then printf '\n'; else printf '%s\n' "$line"; fi
  done <"$1"
}

check_message_file() {
  local matches
  matches=$(commit_message "$1" | find_credits)
  if [[ -n $matches ]]; then
    report 'This commit message' "$matches"
    advice
    exit 1
  fi
}

check_text_file() {
  local matches
  matches=$(find_credits <"$1")
  if [[ -n $matches ]]; then
    report 'This pull request title or description' "$matches"
    advice
    exit 1
  fi
}

check_range() {
  local range=$1 base head commits sha message matches subject count=0 offending=0
  if [[ $range == *...* ]]; then usage "Give a range as <base>..<head>, not $range."; fi
  if [[ $range == *..* ]]; then
    base=${range%%..*}
    head=${range#*..}
    if [[ -z $base || -z $head ]]; then usage "Give a range as <base>..<head>, not $range."; fi
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null || fail "$base is not a commit here."
  else
    head=$range
  fi
  git rev-parse --verify --quiet "$head^{commit}" >/dev/null || fail "$head is not a commit here."

  commits=$(git rev-list --reverse "$range") || fail "git rev-list $range failed."
  if [[ -z $commits ]]; then
    printf 'No commits to check in %s.\n' "$range"
    return
  fi
  while IFS= read -r sha; do
    count=$((count + 1))
    # The raw message: everything after the first blank line of the commit
    # object. This sidesteps any log formatting the user has configured.
    message=$(git cat-file commit "$sha" | sed '1,/^$/d')
    matches=$(printf '%s\n' "$message" | find_credits)
    if [[ -n $matches ]]; then
      offending=$((offending + 1))
      subject=${message%%$'\n'*}
      subject=${subject%$'\r'}
      report "Commit $(git rev-parse --short "$sha") \"$subject\"" "$matches"
    fi
  done <<<"$commits"

  if [[ $offending -gt 0 ]]; then
    advice
    exit 1
  fi
  if [[ $count -eq 1 ]]; then
    printf 'Checked 1 commit; it does not credit an AI tool.\n'
  else
    printf 'Checked %d commits; none credits an AI tool.\n' "$count"
  fi
}

if [[ $# -ne 2 ]]; then usage 'Give one mode and its argument.'; fi
case $1 in
  --message-file | --text-file)
    if [[ ! -f $2 ]]; then fail "$2: no such file."; fi
    if [[ $1 == --message-file ]]; then check_message_file "$2"; else check_text_file "$2"; fi
    ;;
  --range) check_range "$2" ;;
  *) usage "Unknown mode: $1" ;;
esac
