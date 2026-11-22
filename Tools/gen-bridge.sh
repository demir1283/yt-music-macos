#!/bin/bash
# Writes Sources/YTMusicMac/Engine/BridgeScript.swift from Tools/bridge.js, the readable
# source of the script the app runs. build.sh calls it before every build, and GitHub
# Actions checks that the committed copy matches. Edit bridge.js, never the Swift copy.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Tools/bridge.js"
OUT="Sources/YTMusicMac/Engine/BridgeScript.swift"

if grep -q '"""#' "$SRC"; then
  echo "bridge.js contains \"\"\"# and can't be embedded in a Swift raw string." >&2
  exit 1
fi

{
  cat <<'HEAD'
// Generated from Tools/bridge.js — YouTube Music's data API, run by the app in its own
// JavaScriptCore context (NativeCore). No web page is involved.

enum BridgeScript {
    static let source: String = #"""
HEAD
  cat "$SRC"
  [ -z "$(tail -c 1 "$SRC")" ] || echo
  cat <<'TAIL'
"""#

    /// Evaluated before `source`: the one browser global the script expects.
    static let nativePrelude = "var window = globalThis;"
}
TAIL
} > "$OUT.tmp"

if cmp -s "$OUT.tmp" "$OUT"; then
  rm -f "$OUT.tmp"
else
  mv "$OUT.tmp" "$OUT"
  echo "▸ BridgeScript.swift, bridge.js'ten yenilendi"
fi
