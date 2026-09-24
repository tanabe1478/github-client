#!/usr/bin/env bash
set -euo pipefail

BUILD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --build-only)
      BUILD_ONLY=1
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -f "$REPO_ROOT/vendor/imgui/imgui.cpp" ]]; then
  echo "Submodules are not initialized. Run: git submodule update --init" >&2
  exit 1
fi

GLFW_PREFIX="$(brew --prefix glfw 2>/dev/null || true)"
if [[ -z "$GLFW_PREFIX" || ! -f "$GLFW_PREFIX/include/GLFW/glfw3.h" ]]; then
  echo "GLFW was not found. Run: brew install glfw" >&2
  exit 1
fi

if ! command -v mise >/dev/null 2>&1; then
  echo "mise was not found. The MoonBit toolchain is managed by mise.toml." >&2
  exit 1
fi

# The link config passes .native-libs/<platform> as a library search path;
# create it so the linker does not warn about a missing directory.
mkdir -p "$REPO_ROOT/.native-libs/darwin"

cd "$REPO_ROOT"
mise install
# A fresh toolchain has no registry index; `moon update` creates it.
mise exec -- moon update >/dev/null
if [[ "$BUILD_ONLY" -eq 1 ]]; then
  mise exec -- moon build cmd/github_client --target native
else
  mise exec -- moon run cmd/github_client --target native
fi
