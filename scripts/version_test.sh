#!/usr/bin/env bash
#
# version_test.sh — check the pure helpers in install.sh: version
# normalization and the $BLOCK_HOME default.
#
# "latest" needs the GitHub API and is covered by the integration job in
# .github/workflows/test.yml.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=install.sh
source "${here}/install.sh"

failures=0

check_version() {
  local input="$1" want_tag="$2" want_num="$3"
  INPUT_VERSION="$input"
  TAG="" NUM_VERSION=""
  resolve_version
  if [ "$TAG" != "$want_tag" ] || [ "$NUM_VERSION" != "$want_num" ]; then
    printf 'FAIL: %-8s -> TAG=%s NUM=%s (want TAG=%s NUM=%s)\n' \
      "$input" "$TAG" "$NUM_VERSION" "$want_tag" "$want_num"
    failures=$((failures + 1))
  else
    printf 'ok:   %-8s -> TAG=%s NUM=%s\n' "$input" "$TAG" "$NUM_VERSION"
  fi
}

check_home() {
  local input="$1" want="$2"
  INPUT_BLOCK_HOME="$input"
  BLOCK_HOME_DIR=""
  resolve_block_home
  if [ "$BLOCK_HOME_DIR" != "$want" ]; then
    printf 'FAIL: block-home %-20s -> %s (want %s)\n' "'${input}'" "$BLOCK_HOME_DIR" "$want"
    failures=$((failures + 1))
  else
    printf 'ok:   block-home %-20s -> %s\n' "'${input}'" "$BLOCK_HOME_DIR"
  fi
}

check_version "v0.1.0" "v0.1.0" "0.1.0"
check_version "0.1.0"  "v0.1.0" "0.1.0"
check_version " 0.1.0" "v0.1.0" "0.1.0" # surrounding whitespace is trimmed

# The default must match block's own, or a cached store would be restored to a
# directory block never reads.
check_home "" "${HOME}/.local/share/block"
tmp_home="$(mktemp -d)"
check_home "${tmp_home}/store" "${tmp_home}/store"
[ -d "${tmp_home}/store" ] || { printf 'FAIL: block-home directory was not created\n'; failures=$((failures + 1)); }
rm -rf "$tmp_home"

check_platform() {
  local runner_os="$1" runner_arch="$2" want_os="$3" want_arch="$4" want_ext="$5"
  OS="" ARCH="" EXT="" BIN_SUFFIX=""
  RUNNER_OS="$runner_os" RUNNER_ARCH="$runner_arch"
  detect_platform
  if [ "$OS" != "$want_os" ] || [ "$ARCH" != "$want_arch" ] || [ "$EXT" != "$want_ext" ]; then
    printf 'FAIL: %-8s %-6s -> %s/%s.%s (want %s/%s.%s)\n' \
      "$runner_os" "$runner_arch" "$OS" "$ARCH" "$EXT" "$want_os" "$want_arch" "$want_ext"
    failures=$((failures + 1))
  else
    printf 'ok:   %-8s %-6s -> %s/%s.%s\n' "$runner_os" "$runner_arch" "$OS" "$ARCH" "$EXT"
  fi
}

# Every runner block publishes a build for, including the Windows zip and the
# .exe the rest of the script keys off.
check_platform Linux   X64   linux   amd64 tar.gz
check_platform Linux   ARM64 linux   arm64 tar.gz
check_platform macOS   ARM64 darwin  arm64 tar.gz
check_platform Windows X64   windows amd64 zip
check_platform Windows ARM64 windows arm64 zip
if [ "$BIN_SUFFIX" != ".exe" ]; then
  printf 'FAIL: Windows binaries need the .exe suffix, got %s\n' "'${BIN_SUFFIX}'"
  failures=$((failures + 1))
fi

# An unknown runner is refused rather than guessed at.
if ( RUNNER_OS=Plan9 RUNNER_ARCH=X64 detect_platform ) 2>/dev/null; then
  printf 'FAIL: an unknown runner OS was accepted\n'
  failures=$((failures + 1))
else
  printf 'ok:   an unknown runner OS is refused\n'
fi

if [ "$failures" -ne 0 ]; then
  printf '%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all helper tests passed\n'
