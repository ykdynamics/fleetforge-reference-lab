#!/usr/bin/env bash
# Verify that every relative Markdown link in this repository resolves to a file that
# exists, and that every in-page anchor points at a heading that exists in the target.
#
# Read-only: it reads Markdown and touches nothing else. Exits 1 if any link is broken.
set -euo pipefail

cd "$(dirname "$0")/.."

# Slugify a heading the way GitHub does: lowercase, drop anything that is not a word
# character, space or hyphen, then spaces to hyphens.
slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -e 's/[^a-z0-9 _-]//g' -e 's/ /-/g'
}

# Emit "document<TAB>target" for every ](target) in every tracked Markdown file.
link_pairs() {
  local doc target
  while IFS= read -r doc; do
    while IFS= read -r target; do
      [ -n "$target" ] && printf '%s\t%s\n' "$doc" "$target"
    done < <(grep -o '](\([^)]*\))' "$doc" 2>/dev/null | sed 's/^](//; s/)$//')
  done < <(find . -name '*.md' -not -path './.git/*' | sort)
}

# Does $2 exist as a heading slug in Markdown file $1?
has_anchor() {
  local file=$1 want=$2 heading
  while IFS= read -r heading; do
    heading=$(printf '%s' "$heading" | sed 's/^#\{1,6\}[[:space:]]*//')
    [ "$(slugify "$heading")" = "$want" ] && return 0
  done < <(grep '^#\{1,6\}[[:space:]]' "$file" 2>/dev/null || true)
  return 1
}

failures=0
checked=0

while IFS=$'\t' read -r doc target; do
  case "$target" in
    ''|http://*|https://*|mailto:*|'#') continue ;;
  esac

  path=${target%%#*}
  anchor=""
  [ "${target#*#}" != "$target" ] && anchor=${target#*#}

  if [ -z "$path" ]; then
    resolved=$doc                      # same-document anchor
  else
    resolved="$(dirname "$doc")/$path"
  fi

  checked=$((checked + 1))

  if [ ! -e "$resolved" ]; then
    printf 'FAIL %s -> %s (no such file: %s)\n' "$doc" "$target" "$resolved"
    failures=$((failures + 1))
    continue
  fi

  [ -n "$anchor" ] || continue
  case "$resolved" in *.md) ;; *) continue ;; esac

  if ! has_anchor "$resolved" "$anchor"; then
    printf 'FAIL %s -> %s (no heading matching #%s in %s)\n' "$doc" "$target" "$anchor" "$resolved"
    failures=$((failures + 1))
  fi
done < <(link_pairs)

if [ "$failures" -gt 0 ]; then
  printf 'FAIL %d broken link(s) out of %d checked\n' "$failures" "$checked"
  exit 1
fi

printf 'PASS %d relative Markdown link(s) and anchor(s) resolve\n' "$checked"
