# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Workflows should pin the major tag — `nao1215/setup-block@v0` — which moves to
the newest `v0.x.y` release. Pin a full version instead when you need the
action itself to stay still.

## [Unreleased]

## [0.1.0] - 2026-08-22

The first release, alongside [block v0.1.0](https://github.com/nao1215/block/releases/tag/v0.1.0).

### Added
- Installs a prebuilt `block` binary on Linux, macOS and Windows, on x86-64
  and arm64 — every platform block itself publishes a build for. No Go
  toolchain and no `go build` on the runner.
- `version` selects a release (`v0.1.0`, `0.1.0`) or takes `latest`, and the
  resolved version is an output.
- Verifies the download against `checksums.txt` by default, and can also
  verify the cosign signature over that file (`verify-signature`) and the
  GitHub build provenance of the archive (`verify-attestation`).
- Caches `$BLOCK_HOME` keyed by the project's `block.lock`, so a workflow
  whose lockfile has not moved installs nothing and downloads nothing. Reports
  `cache-hit`.
- `sync: "true"` runs `block sync` after installing, so later steps can call
  `block exec` — or the shims, since `$BLOCK_HOME/shims` is on `PATH`.
- `working-directory` points at the `block.toml` and `block.lock` to use, for
  monorepos where they are not at the root.
- Exports `$BLOCK_HOME` and adds the install directory to `PATH` for the steps
  that follow, both switchable.
- The install script reads every pipeline to the end. A reader that stops
  early — `grep -m1`, `head -n1` — sends SIGPIPE to whatever is still writing,
  and under `set -o pipefail` that failed the action with
  `printf: write error: Broken pipe` after it had already resolved the answer.
  Found by the integration test on its first run against a real release, which
  is what that test is gated on block having.
- An integration test that installs block on all five supported runners,
  syncs a real toolchain, and proves it runs through `block exec` and through
  the shims.

[Unreleased]: https://github.com/nao1215/setup-block/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nao1215/setup-block/releases/tag/v0.1.0
