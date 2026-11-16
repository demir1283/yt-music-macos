#!/bin/bash
# Checks everything that would be published for secrets and personal files.
# Run it before every push:   ./release-check.sh
# It exits with an error (and lists the problems) if anything looks sensitive.
set -uo pipefail
cd "$(dirname "$0")"

# The files that would be committed: tracked + new, minus .gitignore'd ones.
if [ -d .git ]; then
  FILES="$(git ls-files --cached --others --exclude-standard)"
else
  FILES="$(find . -type f \
    -not -path './.build/*' -not -path './.swiftpm/*' -not -path './_to_delete/*' \
    -not -path './Screenshots-raw/*' -not -path '*.app/*' -not -name '.DS_Store' \
    -not -name 'profile.txt' -not -name '*.log' | sed 's|^\./||')"
fi

problems=0
flag() { echo "  ✗ $1"; problems=$((problems + 1)); }

echo "▸ Files that must never be published"
while IFS= read -r f; do
  case "$f" in
    *.log|profile.txt|profile.sample.txt|*.binarycookies|*.cookies|.env|*/.env) flag "$f" ;;
    _to_delete/*|Screenshots-raw/*|.build/*|*.app/*) flag "$f" ;;
  esac
done <<< "$FILES"

echo "▸ Secrets, session data and personal information"
# (This script is skipped: it contains the patterns themselves.)
TEXT_FILES="$(echo "$FILES" | grep -Ev '\.(png|jpg|jpeg|icns|gif)$' | grep -v '^release-check\.sh$' || true)"
check() {   # $1 = description, $2 = regex
  local hits
  hits="$(echo "$TEXT_FILES" | tr '\n' '\0' | xargs -0 grep -nIE "$2" 2>/dev/null | cut -c1-160)"
  if [ -n "$hits" ]; then
    flag "$1:"
    echo "$hits" | sed 's/^/      /'
  fi
}
check "Google API key"            'AIza[0-9A-Za-z_-]{30,}'
check "Google session cookie"     '(^|[^A-Za-z])(SAPISID|APISID|HSID|SSID|SID|SIDCC|LOGIN_INFO|__Secure-[0-9A-Za-z-]+)=[A-Za-z0-9_/+-]{8,}'
check "OAuth / bearer token"      'ya29\.[0-9A-Za-z_-]{20,}|Bearer [0-9A-Za-z._-]{20,}'
check "GitHub token"              'gh[pousr]_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{30,}'
check "Private key"               '-----BEGIN [A-Z ]*PRIVATE KEY-----'
check "Personal e-mail address"   '[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|icloud|me|yahoo|yandex|proton(mail)?)\.[a-z]{2,}'
check "Home folder path"          '/Users/[A-Za-z0-9._-]+/'
check "YouTube visitor id"        'VISITOR_INFO1_LIVE=|"visitorData" *: *"[A-Za-z0-9%_-]{16,}'

echo "▸ Screenshot metadata"
for img in $(echo "$FILES" | grep -E '\.(png|jpg|jpeg)$' || true); do
  if command -v mdls >/dev/null 2>&1; then
    meta="$(mdls -raw -name kMDItemWhereFroms "$img" 2>/dev/null)"
    [ -n "$meta" ] && [ "$meta" != "(null)" ] && flag "$img has download-origin metadata"
  fi
done

echo "▸ Large files (over 5 MB)"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  size=$(wc -c < "$f")
  [ "$size" -gt 5242880 ] && flag "$f ($((size / 1048576)) MB)"
done <<< "$FILES"

echo
if [ "$problems" -eq 0 ]; then
  echo "✓ Nothing sensitive found in $(echo "$FILES" | grep -c .) files. Safe to publish."
else
  echo "✗ $problems problem(s) found. Fix them before publishing."
  exit 1
fi
