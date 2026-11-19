"""Generate the official lockfile while retaining reviewed full-SHA workflows."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# The test workflow runs this action as `uses: ./`, and action.yml calls
# actions/cache. The generator cannot follow a `./` action, but the runner
# still demands a lockfile pin for every action it runs, nested ones included.
# So action.yml is scanned as one more file next to the workflows, which
# records its actions/cache pin, and the `./` references only warn.
ACTION_FILE = 'action.yml'


def generator_args(originals):
    return ['--ignore-local-actions',
            *sorted(path.relative_to(ROOT).as_posix() for path in originals)]


def workflow_refs(originals):
    """Collect repository-level action keys; action subpaths share one pin."""
    result = {}
    for path, data in originals.items():
        refs = set()
        for raw in re.findall(r'^\s*(?:-\s*)?uses:\s*[\'\"]?([^\s\'\"#]+)', data.decode(), re.M):
            if raw.startswith('./'):
                continue
            # Reusable workflows are outside the caller's action lockfile, and
            # the SLSA generator only accepts a tag reference.
            if re.search(r'/\.github/workflows/[^/@]+\.ya?ml@', raw):
                continue
            match = re.fullmatch(r'([^/]+/[^/@]+)(?:/[^@]+)?@([0-9a-f]{40})', raw)
            if not match:
                raise ValueError(f'{path}: expected a full-SHA external reference')
            refs.add(match[1].lower()+'@'+match[2])
        result[path.relative_to(ROOT).as_posix()] = refs
    return result


def lock_sections(text):
    """Read only the pinned generator's layout and reject unknown formats."""
    if "version: 'v0.0.3'\nworkflows:\n" not in text or '\ndependencies:\n' not in text:
        raise ValueError('unsupported actions-lock layout; review the generator upgrade')
    workflows_text, dependencies_text = text.split('\ndependencies:\n', 1)
    workflows = {}
    for key, block in re.findall(r"^    '([^']+)':\n((?:        .*\n)*)", workflows_text+'\n', re.M):
        workflows[key] = set(re.findall(r"^        - '([^']+)'$", block, re.M))
    dependencies = {}
    for key, block in re.findall(r"^    '([^']+)':\n((?:        .*\n)*)", dependencies_text, re.M):
        commit = re.search(r"^        commit: 'sha1-([0-9a-f]{40})'$", block, re.M)
        if not commit or key in dependencies:
            raise ValueError(f'invalid dependency entry: {key}')
        dependencies[key] = commit[1]
    if not workflows or not dependencies:
        raise ValueError('empty or unsupported actions-lock sections')
    return workflows, dependencies


def check_exact_refs(text, expected):
    workflows, dependencies = lock_sections(text)
    # A workflow that only calls local ./ workflows is written as `[]`.
    nonempty = lambda refs: {k: v for k, v in refs.items() if v}
    if nonempty(workflows) != nonempty(expected):
        raise ValueError('lockfile workflow references differ from the full-SHA workflows')
    for refs in expected.values():
        for key in refs:
            if dependencies.get(key) != key.rsplit('@', 1)[1]:
                raise ValueError(f'lockfile lacks the exact SHA dependency: {key}')


def retain_sha_keys(text, expected):
    """Translate only aliases whose official resolution equals the reviewed SHA."""
    _, dependencies = lock_sections(text)
    aliases = {}
    for refs in expected.values():
        for key in refs:
            repo, sha = key.rsplit('@', 1)
            matches = [name for name, commit in dependencies.items()
                       if name.rsplit('@', 1)[0] == repo and commit == sha]
            if not matches:
                raise ValueError(f'official generator did not resolve the reviewed pin: {key}')
            for name in matches:
                if name != key:
                    if key in dependencies:
                        raise ValueError(f'ambiguous aliases for {key}; review the lockfile')
                    aliases[name] = key
    # Only complete quoted keys and list entries are replaced. Metadata (ref,
    # commit, owner/repository IDs) and every transitive edge remain intact.
    text = re.sub(r"'([^']+)'", lambda m: "'"+aliases.get(m[1], m[1])+"'", text)
    check_exact_refs(text, expected)
    return text


def main(check=False):
    originals = {path: path.read_bytes() for path in (ROOT/'.github/workflows').glob('*.y*ml')}
    action_file = ROOT/ACTION_FILE
    if action_file.exists():
        originals[action_file] = action_file.read_bytes()
    expected = workflow_refs(originals)
    lock = ROOT/'.github/workflows/actions.lock'
    if check:
        check_exact_refs(lock.read_text(), expected)
        print(f'exact SHA lockfile coverage: {len(expected)} workflows')
        return
    try:
        subprocess.run(['gh', 'actions-lock', *generator_args(originals)], cwd=ROOT, check=True)
    finally:
        # v0.4.1 renders tags for SHA inputs; Scorecard still reads workflows,
        # and action.yml keeps its SHA pin too.
        for path, data in originals.items():
            path.write_bytes(data)
    lock.write_text(retain_sha_keys(lock.read_text(), expected))
    subprocess.run(['gh', 'actions-lock', '--verify', *generator_args(originals)], cwd=ROOT, check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='check exact SHA coverage without writes or network')
    main(check=parser.parse_args().check)
