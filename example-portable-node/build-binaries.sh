#!/usr/bin/env bash
# Cross-compile the portable-node loader into native executables with Bun.
# Usage: ./build-binaries.sh [target ...]   (default: all 6 targets)
#   e.g. ./build-binaries.sh darwin-arm64 linux-x64
# Output: bin/portable-node-<os>-<arch>[.exe] + bin/SHA256SUMS
set -euo pipefail

cd "$(dirname "$0")"

command -v bun >/dev/null 2>&1 || {
  echo "bun not found. Install: curl -fsSL https://bun.sh/install | bash" >&2
  exit 1
}

ENTRY="src/portable-node-loader.ts"
OUT_DIR="bin"
ALL_TARGETS=(darwin-arm64 darwin-x64 linux-arm64 linux-x64 windows-arm64 windows-x64)
TARGETS=("${@:-${ALL_TARGETS[@]}}")

mkdir -p "$OUT_DIR"

for t in "${TARGETS[@]}"; do
  ext=""
  [[ "$t" == windows-* ]] && ext=".exe"
  out="$OUT_DIR/portable-node-$t$ext"
  echo "→ bun-$t  ⇒  $out"
  bun build "$ENTRY" --compile --minify --target="bun-$t" --outfile "$out"
done

# Checksums for upload/verification (shasum on macOS, sha256sum on Linux).
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
(cd "$OUT_DIR" && $SHA portable-node-* > SHA256SUMS)

echo
ls -lh "$OUT_DIR"
