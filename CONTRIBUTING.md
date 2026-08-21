# Contributing

Thanks for looking. This repository is one composite GitHub Action: an
`action.yml` and a POSIX shell script. That makes it small enough to read in
one sitting, and small enough that every change should be easy to justify.

## What changes are welcome

- A runner or architecture the action does not handle yet.
- A failure mode that reports badly — a message that does not say what to do
  next is a bug here.
- Documentation: the README, the cookbook under `doc/`, and the site under
  `website/` are all fair game.

## What belongs in block instead

This action installs the CLI and gets out of the way. It never resolves a
version, never writes `block.lock`, and never installs a tool the lockfile
does not name. Anything that would change those belongs in
[block](https://github.com/nao1215/block), not here — CI is exactly where
those guarantees matter.

So there is no "update the toolchain" input, and there will not be one.

## Running the checks

```shell
shellcheck -x scripts/install.sh scripts/version_test.sh
bash scripts/version_test.sh
```

`actionlint` checks the workflows, and CI runs it. The integration job
installs block on every supported runner and proves the synced toolchain
actually executes, using the tiny project under `testdata/project`.

The documentation site builds with Hugo:

```shell
make website
make website-serve
```

## Pull requests

- One change per pull request, with a
  [Conventional Commits](https://www.conventionalcommits.org/) subject.
- Say which runners you tried it on.
- CI has to be green. If a check is wrong, fix the check in the same pull
  request and say why.

## Code of conduct

[CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md). It is one sentence.
