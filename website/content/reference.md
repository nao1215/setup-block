---
title: Reference
description: "Every input and output of the setup-block action, and how the toolchain cache is keyed."
toc: true
---

## Inputs

| Name | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Version of block to install (`v0.1.0`, `0.1.0`, or `latest`). |
| `github-token` | `${{ github.token }}` | Token for API requests and downloads. Also exported as `GITHUB_TOKEN` for `block sync`. |
| `install-dir` | `$HOME/.block/bin` | Where the `block` binary is installed. |
| `verify-checksum` | `true` | Verify the archive against `checksums.txt`. |
| `verify-signature` | `false` | Verify `checksums.txt` with its cosign bundle. Requires `cosign` on `PATH`. |
| `verify-attestation` | `false` | Verify build provenance with `gh attestation verify`. Requires the `gh` CLI. |
| `add-to-path` | `true` | Add the install directory to `PATH` for later steps. |
| `block-home` | `~/.local/share/block` | The `$BLOCK_HOME` directory, exported for later steps. |
| `cache` | `true` | Cache `$BLOCK_HOME`, keyed by `block.lock`. |
| `working-directory` | `.` | Directory holding `block.toml` and `block.lock`. |
| `sync` | `false` | Run `block sync` after installing. |

## Outputs

| Name | Description |
| --- | --- |
| `version` | The resolved version that was installed. |
| `bin-path` | Absolute path to the installed `block` binary. |
| `install-dir` | Directory the binary was installed into. |
| `block-home` | The `$BLOCK_HOME` exported for later steps. |
| `cache-hit` | `true` when the toolchain cache was restored exactly. Empty when caching is disabled. |

## The cache key

```text
block-<runner os>-<runner arch>-<hash of working-directory/block.lock>
```

There are no `restore-keys`. A store restored from a different lockfile would
be verified and then mostly discarded, since block installs per version and
per artifact digest; re-downloading what actually changed is both simpler and
faster. Set `cache: "false"` when a workflow manages `$BLOCK_HOME` itself.

## Supply-chain checks

```yaml
- uses: sigstore/cosign-installer@v3
- uses: nao1215/setup-block@v0
  with:
    verify-signature: "true"
    verify-attestation: "true"
```

`verify-signature` checks the cosign bundle published for `checksums.txt`,
which transitively covers every artifact listed there. `verify-attestation`
checks the build provenance GitHub recorded for the archive.

Both are opt-in because each needs a tool on the runner — `cosign` and `gh`
respectively — and neither replaces the SHA-256 check, which is on by default.

## Errors you might see

| Message | Meaning |
| --- | --- |
| `block does not ship Windows builds…` | Use a Linux or macOS runner. |
| `failed to download block_…tar.gz` | The requested release or platform does not exist. |
| `checksum mismatch for …` | The download did not match `checksums.txt`. Nothing is installed. |
| `block.lock not found; run "block lock"` | `sync: "true"` ran in a directory without a lockfile. Check `working-directory`. |
| `block.lock is stale; run "block lock"` | `block.toml` changed and the lockfile was not updated. Lock it in a pull request, not in CI. |
