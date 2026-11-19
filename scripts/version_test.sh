#!/usr/bin/env bash
#
# version_test.sh — check the pure helpers in install.sh: version
# normalization and the $BLOCK_HOME default.
#
# "latest" is checked against canned API responses here, and against the real
# API by the integration job in .github/workflows/test.yml.
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
check_version $'v0.8.0\n' "v0.8.0" "0.8.0" # a trailing newline from a multi-line YAML value
check_version $'\tv0.8.0 ' "v0.8.0" "0.8.0"
check_version "v10.20.30" "v10.20.30" "10.20.30" # multi-digit components
check_version "v1.0.0-rc.1" "v1.0.0-rc.1" "1.0.0-rc.1" # pre-release suffix is kept
check_version "1.0.0-rc.1"  "v1.0.0-rc.1" "1.0.0-rc.1"

# check_latest feeds resolve_version a canned API response, so any input that
# means "latest" must come out as the tag in that response.
check_latest() {
  local input="$1" body="$2" want="$3"
  INPUT_VERSION="$input"
  TAG="" NUM_VERSION=""
  LATEST_BODY="$body"
  gh_curl() { printf '%s\n' "$LATEST_BODY"; }
  resolve_version
  if [ "$TAG" != "$want" ] || [ "$NUM_VERSION" != "${want#v}" ]; then
    printf 'FAIL: latest %-8q -> TAG=%s NUM=%s (want %s)\n' "$input" "$TAG" "$NUM_VERSION" "$want"
    failures=$((failures + 1))
  else
    printf 'ok:   latest %-8q -> TAG=%s\n' "$input" "$TAG"
  fi
  unset -f gh_curl
}

check_latest "latest" '{"url":"https://api.github.com/repos/nao1215/block/releases/1","tag_name":"v0.8.0","name":"v0.8.0"}' v0.8.0
check_latest ""       '{"tag_name":"v0.8.0"}' v0.8.0 # the input left empty means latest
check_latest "  "     '{"tag_name":"v0.8.0"}' v0.8.0 # whitespace only means latest too
# A release lists every asset, so the API response outgrows a pipe buffer; the
# tag must come out without a pipe whose reader stops early.
check_latest "latest" "$(printf '{\n  "tag_name": "v0.8.0",\n  "assets": ["%s"]\n}\n' "$(head -c 300000 /dev/zero | tr '\0' 'x')")" v0.8.0

# expect_failure NAME FRAGMENT INPUT [BODY]: resolve_version must stop with an
# error naming FRAGMENT, without building a tag from the input. With BODY the
# API answers it; without BODY any API call is itself a failure.
expect_failure() {
  local name="$1" frag="$2" input="$3" body="${4-}" out status
  INPUT_VERSION="$input"
  LATEST_BODY="$body"
  if [ $# -ge 4 ]; then
    gh_curl() { printf '%s\n' "$LATEST_BODY"; }
  else
    gh_curl() { printf 'gh_curl must not be called for %s\n' "$INPUT_VERSION" >&2; return 1; }
  fi
  set +e
  out="$( (resolve_version) 2>&1)"
  status=$?
  set -e
  unset -f gh_curl
  case "$status:$out" in
    0:*)
      printf 'FAIL: %s was accepted\n' "$name"
      failures=$((failures + 1))
      ;;
    *"$frag"*)
      printf 'ok:   %s rejected\n' "$name"
      ;;
    *)
      printf 'FAIL: %s failed without naming %s: %s\n' "$name" "$frag" "$out"
      failures=$((failures + 1))
      ;;
  esac
}

expect_failure "latest without tag_name" "could not determine" "latest" '{"message":"Not Found"}'
expect_failure "vv0.8.0 (doubled prefix)" "invalid version" "vv0.8.0"
expect_failure "V0.8.0 (upper-case prefix)" "invalid version" "V0.8.0"
expect_failure "Latest (only the exact word means latest)" "invalid version" "Latest"
expect_failure "v (prefix without a version)" "invalid version" "v"
expect_failure "0.8 (missing patch)" "invalid version" "0.8"
expect_failure "0.8.0.0 (extra component)" "invalid version" "0.8.0.0"
expect_failure "v0.8.0 beta (inner word)" "invalid version" "v0.8.0 beta"
expect_failure "0.8.0/../x (path segments)" "invalid version" "0.8.0/../x"

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
