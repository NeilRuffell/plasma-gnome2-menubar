#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
OUT="$DIST/gnome2-menubar-plasma6.plasmoid"

mkdir -p "$DIST"
rm -f "$OUT"
(
  cd "$ROOT"
  zip -qr "$OUT" metadata.json contents
)

echo "Built: $OUT"
