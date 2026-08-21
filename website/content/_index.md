---
title: setup-block
---

Install the [block](https://github.com/nao1215/block) CLI in a workflow,
restore its toolchain cache, and run the tools a repository pinned.

```yaml
- uses: actions/checkout@v4
- uses: nao1215/setup-block@v0
  with:
    sync: "true"
- run: block exec forge test
```

That is the whole CI story. `block sync` installs exactly what `block.lock`
names — no version resolution, no lockfile rewrite — and `block exec` runs
your tools with that toolchain on `PATH`.

## What it does

- Downloads a prebuilt `block` release binary. No Go setup, no `go build`.
- Verifies it against `checksums.txt`, and optionally against its cosign
  signature and GitHub build provenance.
- Exports `$BLOCK_HOME` and caches it, keyed by your `block.lock`, so an
  unchanged toolchain is restored instead of re-downloaded.
- Optionally runs `block sync` so later steps can call `block exec`.

Linux and macOS runners, amd64 and arm64. block ships no Windows builds, so a
Windows runner is refused with an explanation rather than a download error.

## Without syncing

Leave `sync` off when the workflow wants to decide for itself:

```yaml
- uses: nao1215/setup-block@v0
- run: block sync
- run: block exec make test
```

## Watching for new versions

CI never moves a pin: that is a change to `block.lock` and belongs in a pull
request. A scheduled job can tell you when one is worth making — `block lock
--check` exits 2 when a newer release matches the manifest:

```yaml
- uses: nao1215/setup-block@v0
- run: block lock --check
```

See the [reference](reference/) for every input and output.
