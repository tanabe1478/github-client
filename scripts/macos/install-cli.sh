#!/usr/bin/env bash
# Builds the ghclient command-line client in release mode and installs it.
#
# Usage:
#   scripts/macos/install-cli.sh                      # installs to ~/.local/bin
#   INSTALL_DIR=/usr/local/bin scripts/macos/install-cli.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BINARY="$REPO_ROOT/_build/native/release/build/tanabe1478/github-client/cmd/ghclient/ghclient.exe"

cd "$REPO_ROOT"
mkdir -p "$REPO_ROOT/.native-libs/darwin"
mise install >/dev/null
mise exec -- moon build cmd/ghclient --target native --release
if [[ ! -f "$BINARY" ]]; then
  echo "release binary not found: $BINARY" >&2
  exit 1
fi
mkdir -p "$INSTALL_DIR"
install -m 0755 "$BINARY" "$INSTALL_DIR/ghclient"
echo "installed: $INSTALL_DIR/ghclient"
