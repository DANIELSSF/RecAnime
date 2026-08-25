#!/bin/sh
# Fails when a hard-coded color sneaks in outside the design tokens (packages/RecAnimeUI/Sources/RecAnimeUI/Theme).
set -eu
cd "$(dirname "$0")/../.."
violations=$(grep -rnE 'Color\(red:|Color\(hex|#[0-9A-Fa-f]{6}\b|\.(yellow|green|orange|pink|purple|blue|red|mint|teal|indigo|cyan|brown)\b' \
  --include='*.swift' --exclude-dir=.build --exclude-dir=DerivedData --exclude-dir=.swiftpm apple packages 2>/dev/null \
  | grep -v 'packages/RecAnimeUI/Sources/RecAnimeUI/Theme/' \
  | grep -vE '//.*(token|allowed)' || true)
if [ -n "$violations" ]; then
  echo "Palette drift: colors must come from Theme tokens" >&2
  echo "$violations" >&2
  exit 1
fi
echo "theme tokens: ok"
