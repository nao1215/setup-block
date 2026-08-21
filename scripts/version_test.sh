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

# A Windows runner must be refused with an explanation, not a download 404.
if ( RUNNER_OS=Windows RUNNER_ARCH=X64 detect_platform ) 2>/dev/null; then
  printf 'FAIL: a Windows runner was accepted\n'
  failures=$((failures + 1))
else
  printf 'ok:   a Windows runner is refused\n'
fi

if [ "$failures" -ne 0 ]; then
  printf '%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all helper tests passed\n'
