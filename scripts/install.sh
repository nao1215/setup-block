#!/usr/bin/env bash
#
# install.sh — download and install a prebuilt block release binary, and
# export $BLOCK_HOME for the steps that follow.
#
# Runs as a composite-action step on GitHub-hosted runners: Linux, macOS and
# Windows. On Windows it executes under Git Bash, so it relies only on tools
# that ship with every runner (bash, curl, tar, and either unzip or
# PowerShell).
#
# Release artifacts are produced by block's goreleaser config, e.g.:
#   block_0.1.0_linux_amd64.tar.gz
#   block_0.1.0_darwin_arm64.tar.gz
#   block_0.1.0_windows_amd64.zip
#   checksums.txt
#   checksums.txt.sigstore.json
set -euo pipefail

readonly OWNER="nao1215"
readonly REPO="block"
readonly BINARY="block"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { printf '%s\n' "==> $*"; }
die() { printf '%s\n' "ERROR: $*" >&2; exit 1; }

# Emit a GitHub Actions step output when running in Actions; harmless locally.
set_output() {
  local name="$1" value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

# Export a variable to the steps that follow.
set_env() {
  local name="$1" value="$2"
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_ENV"
  fi
}

# curl wrapper that adds the GitHub token when available. Branching avoids
# expanding a possibly-empty array under `set -u` on older bash (macOS 3.2).
gh_curl() {
  if [ -n "${INPUT_GITHUB_TOKEN:-}" ]; then
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" "$@"
  else
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
      -H "X-GitHub-Api-Version: 2022-11-28" "$@"
  fi
}

# ---------------------------------------------------------------------------
# Resolve OS / architecture into goreleaser's naming.
# ---------------------------------------------------------------------------
detect_platform() {
  case "${RUNNER_OS:-}" in
    Linux)   OS="linux"   ; EXT="tar.gz" ; BIN_SUFFIX=""     ;;
    macOS)   OS="darwin"  ; EXT="tar.gz" ; BIN_SUFFIX=""     ;;
    Windows) OS="windows" ; EXT="zip"    ; BIN_SUFFIX=".exe" ;;
    *) die "unsupported runner OS: '${RUNNER_OS:-}' (expected Linux, macOS or Windows)" ;;
  esac

  case "${RUNNER_ARCH:-}" in
    X64|x86_64|amd64) ARCH="amd64" ;;
    ARM64|aarch64)    ARCH="arm64" ;;
    *) die "unsupported runner architecture: '${RUNNER_ARCH:-}' (expected X64 or ARM64)" ;;
  esac
}

# ---------------------------------------------------------------------------
# Resolve the release tag (handles "latest", "v0.1.0" and "0.1.0").
# Sets TAG (with leading v) and NUM_VERSION (without leading v).
# ---------------------------------------------------------------------------
resolve_version() {
  local requested="${INPUT_VERSION:-latest}"
  requested="$(printf '%s' "$requested" | tr -d '[:space:]')"

  if [ -z "$requested" ] || [ "$requested" = "latest" ]; then
    log "Resolving latest block release..."
    local body tag
    body="$(gh_curl "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest")" \
      || die "failed to query the latest release from the GitHub API"
    # Extract tag_name without depending on jq.
    #
    # Every stage reads its input to the end. Under `set -o pipefail` a reader
    # that stops early — grep -m1, head -n1, awk with exit — sends SIGPIPE to
    # whatever is still writing, and the pipeline then fails the script for a
    # reason that has nothing to do with the answer it just produced. That is
    # what "printf: write error: Broken pipe" was on this line.
    #
    # Splitting on commas first also keeps the greedy .* below inside one JSON
    # field rather than letting it run to the last "tag_name" on the line.
    tag="$(printf '%s' "$body" | tr ',' '\n' | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | awk 'NR==1')"
    [ -n "$tag" ] || die "could not determine the latest release tag (has block been released yet?)"
    requested="$tag"
  fi

  # Normalize: TAG keeps the leading v, NUM_VERSION drops it.
  case "$requested" in
    v*) TAG="$requested"    ; NUM_VERSION="${requested#v}" ;;
    *)  TAG="v${requested}" ; NUM_VERSION="$requested"     ;;
  esac
}

# ---------------------------------------------------------------------------
# Where block keeps downloaded artifacts and installed tools.
# ---------------------------------------------------------------------------
resolve_block_home() {
  BLOCK_HOME_DIR="${INPUT_BLOCK_HOME:-}"
  if [ -z "$BLOCK_HOME_DIR" ]; then
    # block's own default, spelled out here so the cache step has a path.
    BLOCK_HOME_DIR="${HOME}/.local/share/block"
  fi
  mkdir -p "$BLOCK_HOME_DIR"
}

# Convert a path to the runner's native form before writing it to $GITHUB_PATH
# or $GITHUB_ENV. On Windows this script runs under Git Bash, so a POSIX path
# like /c/foo would not resolve for a following PowerShell step; cygpath
# rewrites it to C:\foo.
to_native_path() {
  local path="$1"
  if [ "${OS:-}" = "windows" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s' "$path"
  fi
}

# ---------------------------------------------------------------------------
# Extract the archive into a directory.
# ---------------------------------------------------------------------------
extract_archive() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "$archive" in
  *.tar.gz | *.tgz)
    tar -xzf "$archive" -C "$dest"
    ;;
  *.zip)
    if command -v unzip >/dev/null 2>&1; then
      unzip -oq "$archive" -d "$dest"
    elif command -v pwsh >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1; then
      local ps
      ps="$(command -v pwsh || command -v powershell)"
      "$ps" -NoProfile -NonInteractive -Command \
        "Expand-Archive -Path '${archive}' -DestinationPath '${dest}' -Force"
    else
      die "cannot extract ${archive}: neither unzip nor PowerShell is available"
    fi
    ;;
  *)
    die "unsupported archive format: ${archive}"
    ;;
  esac
}

# ---------------------------------------------------------------------------
# Verify the archive against checksums.txt (SHA-256).
# ---------------------------------------------------------------------------
sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v certutil >/dev/null 2>&1; then
    # Windows fallback: certutil prints the hash on the second line.
    certutil -hashfile "$file" SHA256 | sed -n '2p' | tr -d '[:space:]'
  else
    return 1
  fi
}

verify_checksum() {
  local archive="$1" checksums="$2" name="$3"
  local expected actual
  # awk 'NR==1' rather than head -n1: head stops reading, which sends SIGPIPE
  # to the stage before it and fails the pipeline under `set -o pipefail`.
  expected="$(grep -E "[[:space:]]\*?${name//./\\.}$" "$checksums" | awk 'NR==1{print $1}')"
  [ -n "$expected" ] || die "checksum for ${name} not found in checksums.txt"

  actual="$(sha256_of "$archive")" \
    || die "no SHA-256 tool (sha256sum/shasum/certutil) available to verify ${name}"

  expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  actual="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"

  if [ "$expected" != "$actual" ]; then
    die "checksum mismatch for ${name}: expected ${expected}, got ${actual}"
  fi
  log "Checksum OK (${name})"
}

# ---------------------------------------------------------------------------
# Verify checksums.txt itself with its cosign bundle (opt-in). Signing the
# checksums file covers every artifact listed in it.
# ---------------------------------------------------------------------------
verify_signature() {
  local checksums="$1" base_url="$2" workdir="$3"
  command -v cosign >/dev/null 2>&1 \
    || die "verify-signature is enabled but cosign is not on PATH. Add sigstore/cosign-installer before this action."
  local bundle="${workdir}/checksums.txt.sigstore.json"
  gh_curl -o "$bundle" "${base_url}/checksums.txt.sigstore.json" \
    || die "verify-signature is enabled but checksums.txt.sigstore.json could not be downloaded for ${TAG}"
  log "Verifying the cosign signature of checksums.txt..."
  cosign verify-blob "$checksums" \
    --bundle "$bundle" \
    --certificate-identity-regexp "https://github.com/${OWNER}/${REPO}/.github/workflows/release.yml@refs/tags/v.*" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    || die "cosign could not verify checksums.txt for ${TAG}"
  log "Signature OK"
}

# ---------------------------------------------------------------------------
# Verify build provenance with the gh CLI (opt-in).
# ---------------------------------------------------------------------------
verify_attestation() {
  local archive="$1"
  command -v gh >/dev/null 2>&1 \
    || die "verify-attestation is enabled but the gh CLI is not available on this runner"
  if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    die "verify-attestation is enabled but neither GH_TOKEN nor GITHUB_TOKEN is set"
  fi
  log "Verifying build provenance with gh attestation verify..."
  gh attestation verify "$archive" --repo "${OWNER}/${REPO}" \
    || die "build provenance verification failed for $(basename "$archive")"
  log "Attestation OK"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  detect_platform
  resolve_version
  resolve_block_home

  local archive_name="${BINARY}_${NUM_VERSION}_${OS}_${ARCH}.${EXT}"
  local base_url="https://github.com/${OWNER}/${REPO}/releases/download/${TAG}"

  log "Installing ${BINARY} ${TAG} (${OS}/${ARCH})"

  # NOT `local`: the EXIT trap fires after main() returns, when a local would
  # already be out of scope. ${workdir:-} keeps the trap safe even if mktemp
  # itself failed.
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir:-}"' EXIT

  local archive_path="${workdir}/${archive_name}"
  log "Downloading ${base_url}/${archive_name}"
  gh_curl -o "$archive_path" "${base_url}/${archive_name}" \
    || die "failed to download ${archive_name}. Does release ${TAG} exist for ${OS}/${ARCH}?"

  local checksums_path="${workdir}/checksums.txt"
  if [ "${INPUT_VERIFY_CHECKSUM:-true}" = "true" ] || [ "${INPUT_VERIFY_SIGNATURE:-false}" = "true" ]; then
    gh_curl -o "$checksums_path" "${base_url}/checksums.txt" \
      || die "checksums.txt could not be downloaded for ${TAG}"
  fi
  if [ "${INPUT_VERIFY_SIGNATURE:-false}" = "true" ]; then
    verify_signature "$checksums_path" "$base_url" "$workdir"
  fi
  if [ "${INPUT_VERIFY_CHECKSUM:-true}" = "true" ]; then
    verify_checksum "$archive_path" "$checksums_path" "$archive_name"
  else
    log "Checksum verification disabled by input (verify-checksum: false)"
  fi
  if [ "${INPUT_VERIFY_ATTESTATION:-false}" = "true" ]; then
    verify_attestation "$archive_path"
  fi

  local extract_dir="${workdir}/extracted"
  extract_archive "$archive_path" "$extract_dir"

  local bin_name="${BINARY}${BIN_SUFFIX}"
  local src_bin
  # Same reason as above: head -n1 would stop reading while find is still
  # walking, and a second match would kill find with SIGPIPE.
  src_bin="$(find "$extract_dir" -type f -name "$bin_name" | awk 'NR==1')"
  [ -n "$src_bin" ] || die "binary '${bin_name}' not found inside ${archive_name}"

  local install_dir="${INPUT_INSTALL_DIR:-}"
  if [ -z "$install_dir" ]; then
    install_dir="${HOME}/.${BINARY}/bin"
  fi
  mkdir -p "$install_dir"

  local dest_bin="${install_dir}/${bin_name}"
  cp "$src_bin" "$dest_bin"
  chmod +x "$dest_bin" 2>/dev/null || true

  if [ "${INPUT_ADD_TO_PATH:-true}" = "true" ] && [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "$(to_native_path "$install_dir")" >>"$GITHUB_PATH"
  fi

  # Every later step — cached or not — must agree with this action about
  # where the toolchain lives.
  set_env "BLOCK_HOME" "$(to_native_path "$BLOCK_HOME_DIR")"

  log "Installed ${bin_name} -> ${dest_bin}"
  log "BLOCK_HOME=${BLOCK_HOME_DIR}"

  set_output "version" "$TAG"
  set_output "bin-path" "$dest_bin"
  set_output "install-dir" "$install_dir"
  set_output "block-home" "$BLOCK_HOME_DIR"
}

# Only run when executed directly, so tests can source the functions above.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
