# Cookbook

Copyable workflow steps for installing a pinned blockchain toolchain in CI.
Every snippet is a real step; drop it into a job and swap the tool names.

The action installs the [block](https://github.com/nao1215/block) CLI and
nothing else. block is what installs your tools, from `block.lock`, and it
never resolves a version in CI — so nothing here can move a pin.

## Find a recipe by task

| I want to | Go to |
|:--|:--|
| Get the toolchain and run one command | [The whole thing](#the-whole-thing) |
| Install the CLI and drive it myself | [Install without syncing](#install-without-syncing) |
| Pin the version of block itself | [Pin the action's block version](#pin-the-actions-block-version) |
| Run the same job on Linux, macOS and Windows | [A matrix across runners](#a-matrix-across-runners) |
| Keep `block.toml` in a subdirectory | [A monorepo subdirectory](#a-monorepo-subdirectory) |
| Use several toolchains in one workflow | [Two projects in one workflow](#two-projects-in-one-workflow) |
| Understand or change the cache | [Caching](#caching) |
| Verify signatures and provenance | [Supply-chain checks](#supply-chain-checks) |
| Run the tools without typing `block exec` | [Use the shims](#use-the-shims) |
| Fail a pull request whose lockfile is stale | [Guard the lockfile](#guard-the-lockfile) |
| Open a PR when upstream publishes something | [Watch for upstream releases](#watch-for-upstream-releases) |
| Run `forge` inside a Docker build or a service job | [Beyond a plain step](#beyond-a-plain-step) |
| Work out why the action failed | [Read a failure](#read-a-failure) |

## The whole thing

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: nao1215/setup-block@v0
        with:
          sync: "true"
      - run: block exec forge test
```

`sync: "true"` installs exactly what `block.lock` names for this runner. The
step after it has every locked tool on `PATH` through `block exec`.

Runners: Linux, macOS and Windows, on x86-64 and arm64. Which of them your
*tools* have builds for is a different question, and it is answered by
`block.lock` — see [locking for a platform you are not
on](https://nao1215.github.io/block/cookbook/#lock-for-a-platform-you-are-not-on).

## Install without syncing

Leave `sync` off when the job wants to decide for itself when the toolchain is
installed — for example after a step that generates `block.toml`:

```yaml
- uses: nao1215/setup-block@v0
- run: ./scripts/generate-manifest.sh
- run: block sync
- run: block exec make test
```

The default is off, so this is what you get by writing nothing.

## Pin the action's block version

```yaml
- uses: nao1215/setup-block@v0
  with:
    version: v0.1.0        # "0.1.0" works too; "latest" is the default
```

`latest` is fine for a repository that tracks block closely. Pin an exact
version when you want the CLI itself to change only when you say so — the
same argument as pinning your tools, applied one level up.

## A matrix across runners

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v6
      - uses: nao1215/setup-block@v0
        with:
          sync: "true"
      - run: block exec forge test
```

`block.toml` has to name every platform the matrix uses, or `sync` stops on
the runner whose artifact was never resolved:

```toml
platforms = ["linux/amd64", "darwin/arm64", "windows/amd64"]
```

The cache key already includes the runner OS and architecture, so the legs do
not fight over one store.

## A monorepo subdirectory

```yaml
- uses: nao1215/setup-block@v0
  with:
    working-directory: contracts   # where block.toml and block.lock live
    sync: "true"
- run: block exec forge test
  working-directory: contracts
```

`working-directory` decides both where `sync` runs and which `block.lock` the
cache is keyed on. Later steps still need their own `working-directory`,
because block finds `block.toml` by walking up from the directory it is run
in.

## Two projects in one workflow

Use the action once and let block find each project:

```yaml
- uses: nao1215/setup-block@v0
  with:
    working-directory: contracts
    sync: "true"

- run: block sync && block exec rly version
  working-directory: relayer
```

The store is shared, so the second `sync` re-uses everything the first one
already downloaded. Only the first project's `block.lock` is in the cache key;
if the two change independently and you want both to count, run the action
twice with different `working-directory` values, or manage the cache yourself
with `cache: "false"`.

## Caching

`$BLOCK_HOME` holds the downloaded artifacts and the unpacked tools. The
action caches it keyed by the runner OS, its architecture, and the hash of
`block.lock`, so a workflow whose lockfile has not changed re-uses the store
instead of downloading Foundry again.

```yaml
- uses: nao1215/setup-block@v0
  id: setup
  with:
    sync: "true"
- run: echo "restored exactly: ${{ steps.setup.outputs.cache-hit }}"
```

There are no partial-restore keys, on purpose: block re-verifies every
artifact against the lockfile anyway, and a store restored from a different
lockfile would be mostly discarded.

Manage the cache yourself:

```yaml
- uses: nao1215/setup-block@v0
  with:
    cache: "false"
- uses: actions/cache@v4
  with:
    path: ~/.local/share/block
    key: my-own-key-${{ hashFiles('**/block.lock') }}
- run: block sync
```

Put the store inside the workspace when that is what your cache layer wants:

```yaml
- uses: nao1215/setup-block@v0
  with:
    block-home: ${{ github.workspace }}/.block
    sync: "true"
```

## Supply-chain checks

The archive is verified against `checksums.txt` by default. Two stronger
checks are opt-in because each needs a tool on the runner:

```yaml
- uses: sigstore/cosign-installer@v3
- uses: nao1215/setup-block@v0
  with:
    verify-signature: "true"     # cosign-verify checksums.txt
    verify-attestation: "true"   # gh attestation verify the archive
    sync: "true"
```

`verify-signature` checks the cosign bundle block publishes for
`checksums.txt`, which transitively covers every artifact listed in it.
`verify-attestation` checks the build provenance GitHub recorded for the
archive itself; it needs the `gh` CLI and a token, both present on
GitHub-hosted runners.

Each check fails the step rather than warning: a verification you asked for
and did not get is not a verification.

Turning the default off is possible and rarely right:

```yaml
- uses: nao1215/setup-block@v0
  with:
    verify-checksum: "false"
```

## Use the shims

`block sync` writes one file per command into `$BLOCK_HOME/shims`. Adding that
to `PATH` lets a script that knows nothing about block run the locked tools:

```yaml
- uses: nao1215/setup-block@v0
  with:
    sync: "true"
- run: echo "$BLOCK_HOME/shims" >> "$GITHUB_PATH"
- run: forge test          # the version block.lock pinned
- run: ./scripts/e2e.sh    # and so does everything this calls
```

`block exec` needs no `PATH` setup and says what is happening, so prefer it
for the steps you write yourself. The shims are for the scripts you did not.

## Guard the lockfile

`block sync` already fails when `block.toml` and `block.lock` disagree, so a
pull request that edits the manifest without re-locking fails on the sync
step. Giving it a step of its own says so earlier:

```yaml
- uses: nao1215/setup-block@v0
- name: block.lock matches block.toml
  run: block sync
```

To also learn when the pins have fallen behind upstream, without failing the
build for it:

```yaml
- name: Report toolchain updates
  continue-on-error: true
  run: block lock --check
```

`block lock --check` resolves and writes nothing. It exits 0 when the lockfile
is current, 2 when it would change, 1 on error. Keep it out of the required
checks: a release upstream is news, not a broken build.

## Watch for upstream releases

Moving a pin is a change to `block.lock` and belongs in a pull request. A
weekly job can open it:

```yaml
name: Toolchain updates
on:
  schedule: [{ cron: "0 6 * * 1" }]
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: nao1215/setup-block@v0
      - id: check
        # `cmd || echo ...` treats every failure as staleness, including exit 1
        # — a network error or a broken manifest — and would open a pull
        # request from a resolution that never finished. Only 2 means "the
        # lockfile would change"; 1 is an error and has to fail the job.
        run: |
          set +e
          block lock --check
          status=$?
          set -e
          case "$status" in
            0) ;;
            2) echo "stale=2" >> "$GITHUB_OUTPUT" ;;
            *) exit "$status" ;;
          esac
      - if: steps.check.outputs.stale == '2'
        run: block lock
      - if: steps.check.outputs.stale == '2'
        uses: peter-evans/create-pull-request@v7
        with:
          title: "chore: move the toolchain pins forward"
          branch: block/toolchain-update
```

There is deliberately no "update the toolchain" input on this action. CI is
where a pin must not move on its own.

## Beyond a plain step

A service container or a Docker build does not see the runner's `$BLOCK_HOME`,
so install the toolchain inside the image instead — copying `block.toml` and
`block.lock` first makes it a cacheable layer:

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
RUN curl -sSfL https://github.com/nao1215/block/releases/download/v0.1.0/block_0.1.0_linux_amd64.tar.gz \
  | tar xz -C /usr/local/bin block
WORKDIR /src
COPY block.toml block.lock ./
RUN block sync
```

A tool that has to keep running across steps — a devnet, a beacon node — is an
ordinary background process:

```yaml
- uses: nao1215/setup-block@v0
  with:
    sync: "true"
- run: block exec anvil &
- run: block exec forge script script/Deploy.s.sol --broadcast --rpc-url http://127.0.0.1:8545
```

## Read a failure

The runner is not one block publishes a build for:

```text
ERROR: unsupported runner architecture: 'ARM' (expected X64 or ARM64)
```

The version you asked for has no archive for this runner:

```text
ERROR: failed to download block_9.9.9_linux_amd64.tar.gz. Does release v9.9.9 exist for linux/amd64?
```

The download did not match what the release says it should be. Nothing is
installed:

```text
ERROR: checksum mismatch for block_0.1.0_linux_amd64.tar.gz: expected e3b0c442..., got 9f86d081...
```

A stronger check was asked for and the tool that performs it is missing. The
step fails rather than quietly skipping it:

```text
ERROR: verify-signature is enabled but cosign is not on PATH. Add sigstore/cosign-installer before this action.
```

`sync: "true"` was set but the project has no lockfile yet — run `block lock`
once, locally, and commit it:

```text
block: block.lock not found; run "block lock" and "block sync"
```

`block.toml` was edited and `block.lock` was not re-generated:

```text
block: block.lock is stale; run "block lock"
  hermes is declared in block.toml but missing from block.lock
```

`block.toml` does not name this runner's platform:

```text
block: block.lock is stale; run "block lock"
  foundry: block.lock has no artifact for linux/amd64
```

Every message block prints, with the command that fixes it, is in
[block's cookbook](https://nao1215.github.io/block/cookbook/#read-a-refusal).
