<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-1-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

[![Test](https://github.com/nao1215/setup-block/actions/workflows/test.yml/badge.svg)](https://github.com/nao1215/setup-block/actions/workflows/test.yml)
[![Website](https://github.com/nao1215/setup-block/actions/workflows/website.yml/badge.svg)](https://github.com/nao1215/setup-block/actions/workflows/website.yml)
[![Gitleaks](https://github.com/nao1215/setup-block/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/setup-block/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/setup-block/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/setup-block/actions/workflows/trivy.yml)
[![License](https://img.shields.io/github/license/nao1215/setup-block)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/setup-block/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/setup-block)

<p align="center">
  <img src="./doc/img/setup-block-logo.png" alt="setup-block logo" width="460" />
</p>

GitHub Action that installs the [block](https://github.com/nao1215/block) CLI and restores its toolchain cache. block pins the blockchain CLI tools a project depends on, such as Foundry, geth, Lighthouse, Agave and Hermes, so every machine and CI get the same toolchain. The action downloads a prebuilt `block` binary (no Go setup), caches `$BLOCK_HOME` keyed by the lockfile, and can run `block sync` for the steps that follow.

Documentation: https://nao1215.github.io/setup-block/

## Quick start

```yaml
- uses: actions/checkout@v6
- uses: nao1215/setup-block@v0
  with:
    sync: "true"
- run: block exec forge test
```

This installs the toolchain in `block.lock`, and `block exec` runs your tools
with it on `PATH`.

Without `sync`, the action only installs the CLI and leaves the timing to you:

```yaml
- uses: nao1215/setup-block@v0
- run: block sync
- run: block exec make test
```

The [cookbook](./doc/cookbook.md) covers matrices, monorepo subdirectories,
cache control, signature and provenance checks, guarding the lockfile, and
reading a failure.

## Supported runners

Linux, macOS and Windows, on x86-64 and arm64, which is every platform block
publishes a build for. Whether each tool has a build for the runner depends on
`block.lock`; block reports a platform the lockfile does not cover instead of
substituting something else.

## Pin a version

```yaml
- uses: nao1215/setup-block@v0
  with:
    version: v0.8.0        # "0.8.0" works too; "latest" is the default
```

The version must be `latest`, `vX.Y.Z` or `X.Y.Z` (a pre-release suffix such as
`-rc.1` is allowed). Anything else, such as `V0.8.0` or `0.8`, fails the step
before any download.

## Caching

`$BLOCK_HOME` holds the downloaded artifacts and the unpacked tools. The
action caches it keyed by `block.lock`, so a workflow whose lockfile has not
changed re-uses the same store instead of downloading Foundry again:

```yaml
- uses: nao1215/setup-block@v0
  with:
    working-directory: contracts   # where block.toml and block.lock live
    sync: "true"
```

The key is the runner OS, its architecture and the hash of that directory's
`block.lock`. [How the key works](https://nao1215.github.io/setup-block/reference/#the-cache-key).

## Supply-chain checks

The downloaded archive is verified against `checksums.txt` by default. Two
stronger checks are available:

```yaml
- uses: sigstore/cosign-installer@v3
- uses: nao1215/setup-block@v0
  with:
    verify-signature: "true"     # cosign-verify checksums.txt (needs cosign)
    verify-attestation: "true"   # gh attestation verify (needs the gh CLI)
```

Details are in the [reference](https://nao1215.github.io/setup-block/reference/#supply-chain-checks).

## Inputs

| Name | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Version of block to install (`v0.8.0`, `0.8.0`, or `latest`). |
| `github-token` | `${{ github.token }}` | Token for API requests and downloads. Also exported as `GITHUB_TOKEN` for `block sync`. |
| `install-dir` | `$HOME/.block/bin` | Where the `block` binary is installed. |
| `verify-checksum` | `true` | Verify the archive against `checksums.txt`. |
| `verify-signature` | `false` | Verify `checksums.txt` with its cosign bundle. Requires `cosign`. |
| `verify-attestation` | `false` | Verify build provenance with `gh attestation verify`. Requires the `gh` CLI. |
| `add-to-path` | `true` | Add the install directory to `PATH` for later steps. |
| `block-home` | `~/.local/share/block` | The `$BLOCK_HOME` directory, exported for later steps. |
| `cache` | `true` | Cache `$BLOCK_HOME`, keyed by `block.lock`. |
| `working-directory` | `.` | Directory holding `block.toml` and `block.lock`. |
| `sync` | `false` | Run `block sync` after installing. |

## Outputs

| Name | Description |
| --- | --- |
| `version` | The resolved version that was installed (e.g. `v0.8.0`). |
| `bin-path` | Absolute path to the installed `block` binary. |
| `install-dir` | Directory the binary was installed into. |
| `block-home` | The `$BLOCK_HOME` exported for later steps. |
| `cache-hit` | `true` when the toolchain cache was restored exactly. Empty when caching is disabled. |

## What this action does not do

It never resolves versions, writes `block.lock`, or installs a tool the
lockfile does not name. `block sync` never resolves, and `block lock` is the
only command that moves a pin, so there is no input for updating the toolchain
in CI. A pin change belongs in a pull request; a scheduled job can report when
one is due:

```yaml
- uses: nao1215/setup-block@v0
- run: block lock --check   # exit 2 when a newer version is available
```

## Related

- [setup-block documentation](https://nao1215.github.io/setup-block/)
- [Cookbook](./doc/cookbook.md): workflow steps indexed by task
- [block](https://github.com/nao1215/block): the CLI this action installs
- [block-registry](https://github.com/nao1215/block-registry): the tools block can install

## Testing

| Technique | Bug class caught here |
|---|---|
| [Version input boundaries](scripts/version_test.sh) | `latest`, empty, whitespace, `v`-less and pre-release inputs resolving to the wrong tag, malformed versions reaching the download URL, a wrong `$BLOCK_HOME` default and a wrong asset name for a runner |
| [Real-runner installs](.github/workflows/test.yml) | Asset naming, extraction, checksum, cache and `PATH` breakage on Linux, macOS and Windows (amd64 / arm64), a synced toolchain or its shims not running, pinned and `v`-less versions installing something else, and invalid versions or a missing release passing silently |

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](./CONTRIBUTING.md).
A GitHub Star also helps.

## LICENSE

The setup-block project is licensed under the terms of [MIT LICENSE](./LICENSE).

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://debimate.jp/"><img src="https://avatars.githubusercontent.com/u/22737008?v=4?s=75" width="75px;" alt="CHIKAMATSU Naohiro"/><br /><sub><b>CHIKAMATSU Naohiro</b></sub></a><br /><a href="https://github.com/nao1215/setup-block/commits?author=nao1215" title="Code">💻</a> <a href="https://github.com/nao1215/setup-block/commits?author=nao1215" title="Documentation">📖</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
