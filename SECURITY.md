# Security policy

## What this action does

setup-block downloads a prebuilt [block](https://github.com/nao1215/block)
release archive onto a runner, verifies it, and puts the binary on `PATH`. It
runs `scripts/install.sh`, a POSIX shell script committed in this repository —
there is no compiled component and no third-party action in the install path.

Anything it installs beyond that is block's doing, from your `block.lock`.

## Reporting a vulnerability

Report security issues privately, not through public issues or pull requests.

- Email: n.chika156@gmail.com
- Or use the "Report a vulnerability" button on the repository's Security tab.

Reports in these areas are especially valuable:

- A way to make the action install an archive that is not the one
  `checksums.txt` names, or to make a failed verification look like a passed
  one.
- A way for an input (`version`, `install-dir`, `block-home`,
  `working-directory`) to inject shell, escape the runner workspace, or write
  outside the install directory.
- A token or secret reaching a log, a `GITHUB_OUTPUT`, or a downloaded
  artifact.
- A path where `verify-signature` or `verify-attestation` is enabled and the
  step still succeeds without the check having run.

Include the workflow snippet and the runner OS.

## What is verified by default

The downloaded archive is checked against the release's `checksums.txt` before
anything is extracted. Two stronger checks are opt-in because each needs a
tool on the runner:

- `verify-signature: "true"` — cosign-verifies `checksums.txt` against the
  keyless bundle block publishes, which transitively covers every artifact
  listed in it. Needs `cosign`.
- `verify-attestation: "true"` — verifies the archive's GitHub build
  provenance. Needs the `gh` CLI and a token.

A verification you enabled and could not be completed fails the step. It is
never downgraded to a warning.

## Pinning

`version: latest` installs whatever block published most recently. Pin an
exact version, and pin this action to a commit SHA, when you want CI to change
only when you change it:

```yaml
- uses: nao1215/setup-block@<sha>
  with:
    version: v0.1.0
```
