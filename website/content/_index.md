---
title: setup-block
---

Install the [block](https://github.com/nao1215/block) CLI in a workflow,
restore its toolchain cache, and run the tools a repository pinned.

```yaml
- uses: actions/checkout@v6
- uses: nao1215/setup-block@v0
  with:
    sync: "true"
- run: block exec forge test
```

`block sync` installs what `block.lock` names without resolving versions or
rewriting the lockfile, and `block exec` runs your tools with that toolchain on
`PATH`.

## What it does

- Downloads a prebuilt `block` release binary. No Go setup, no `go build`.
- Verifies it against `checksums.txt`, and optionally against its cosign
  signature and GitHub build provenance.
- Exports `$BLOCK_HOME` and caches it, keyed by your `block.lock`, so an
  unchanged toolchain is restored instead of re-downloaded.
- Optionally runs `block sync` so later steps can call `block exec`.

It runs on Linux, macOS and Windows, on x86-64 and arm64, which is every
platform block publishes a build for. Whether each tool has a build for the
runner depends on `block.lock`.

## Without syncing

Leave `sync` off when the workflow wants to decide for itself:

```yaml
- uses: nao1215/setup-block@v0
- run: block sync
- run: block exec make test
```

## Watching for new versions

CI never moves a pin; that change to `block.lock` belongs in a pull request.
In a scheduled job, `block lock --check` exits 2 when a newer release matches
the manifest:

```yaml
- uses: nao1215/setup-block@v0
- run: block lock --check
```

The [cookbook](/cookbook/) covers matrices, monorepo subdirectories, cache
control, signature and provenance checks, guarding the lockfile, and reading a
failure. The [reference](/reference/) lists every input and output.
