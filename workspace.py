"""Validate and test the pinned component submodules."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT / "components"


def run(command, cwd=ROOT):
    subprocess.run([str(item) for item in command], cwd=cwd, check=True, timeout=180)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['doctor', 'test'])
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        parser.error('Python 3.11+ required')
    if not __debug__:
        parser.error('Unset PYTHONOPTIMIZE; model checks use assertions')

    manifest = json.loads((ROOT / 'workspace.json').read_text())
    if manifest.get('schema') != 1 or manifest.get('mode') != 'submodule-workspace':
        parser.error('Expected schema 1 submodule-workspace manifest')
    components = manifest['components']
    folders = {}
    for name, record in components.items():
        if not re.fullmatch(r'[a-z][a-z0-9-]*', name):
            parser.error('Invalid component folder name')
        folder = ROOT if name == 'soc' else WORKSPACE / name
        if not folder.is_dir():
            parser.error(f'Missing component folder: {name}')
        for required in record['required_files']:
            relative = Path(required)
            if relative.is_absolute() or '..' in relative.parts:
                parser.error(f'Invalid required file path for {name}')
            if not (folder / relative).is_file():
                parser.error(f'Missing required file: {folder.name}/{required}')
        folders[name] = folder

    print(f'PASS {len(components)} component folders found; testing checked-out files', flush=True)
    for tool in ['iverilog', 'vvp']:
        if not shutil.which(tool):
            parser.error(f'Missing {tool}; install Icarus Verilog')
    if args.command == 'doctor':
        print('PASS doctor: component files, Python and Icarus available')
        return

    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    vectors = build / 'mac-vectors.txt'
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v'], cwd=folders['software'])
    run([sys.executable, folders['software'] / 'generate_vectors.py',
         '--contract', folders['architecture'] / 'contracts/mac-v0.json', '--output', vectors])
    run([sys.executable, folders['verification'] / 'run.py',
         '--rtl-root', folders['rtl-compute'], '--vectors', vectors])
    print('PASS integration: contract -> software -> compute RTL -> independent verification')
    scaffolds = ', '.join(name for name, record in components.items() if record['status'] == 'scaffold')
    print(f'Scope: MAC only. Implementation pending: {scaffolds}.')


if __name__ == '__main__':
    main()
