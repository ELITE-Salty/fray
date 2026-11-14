#!/usr/bin/env python3
"""Export a signed iOS build on a Mac, or package source for a future Mac build."""
import argparse
import hashlib
import json
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'apps/fray'


def version():
    match = re.search(r'^version:\s*([\w.+-]+)\s*$', (APP / 'pubspec.yaml').read_text(), re.M)
    if not match:
        raise ValueError('Cannot read the app version from pubspec.yaml.')
    return match[1]


def package_source(output):
    """Explicit tracked-source allowlist: no build output, credentials or backend data."""
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    extra = {'scripts/build-ios.py', 'docs/ios.md', 'apps/fray/ios/Runner/Runner.entitlements'}
    paths = set(paths) | extra
    selected = []
    for name in sorted(paths):
        if not (name.startswith(('apps/fray/lib/', 'apps/fray/assets/', 'apps/fray/ios/')) or
                name in extra or name in {'apps/fray/pubspec.yaml', 'apps/fray/pubspec.lock'}):
            continue
        path = ROOT / name
        if path.suffix in {'.p8', '.p12', '.pem', '.key', '.mobileprovision', '.ipa'}:
            raise ValueError('Signing material must not be included in a source bundle.')
        if path.is_symlink() or not path.is_file():
            raise ValueError('Missing or symlinked source: ' + name)
        selected.append((name, path))
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'fray-ios-source-{version()}.zip'
    with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr('READ-ME-FIRST.txt',
            'FRAY iOS SOURCE — NOT AN INSTALLER\n\n'
            'No IPA or compiled iOS application is included. Extract this folder on a Mac,\n'
            'then follow docs/ios.md to install Flutter/Xcode and configure Apple signing.\n'
            'The build script exports signed files to dist/ios/.\n')
        for name, path in selected:
            bundle.write(path, name)
    print('Source archive (NOT installable): ' + str(target))
    return target


def export_ipa(args, output):
    if platform.system() != 'Darwin':
        raise ValueError('An iOS IPA requires macOS and Xcode. This machine cannot build one. '
                         'Use --source-only to prepare a source archive; that archive is not installable.')
    for tool in ['flutter', 'xcodebuild', 'codesign', 'ditto']:
        if not shutil.which(tool):
            raise ValueError(f'{tool} is required. See docs/ios.md.')
    url = urlsplit(args.api_url)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('--api-url must be an HTTPS origin without credentials, path, query or fragment.')
    command = ['flutter', 'build', 'ipa', '--release', '--dart-define=FRAY_API_URL=' + args.api_url]
    if args.export_options:
        options = args.export_options.resolve()
        with options.open('rb') as file:
            plistlib.load(file)
        command += ['--export-options-plist=' + str(options)]
    else:
        command += ['--export-method=' + (args.method or 'app-store')]
    if args.build_number:
        command += ['--build-number=' + args.build_number]
    subprocess.run(['xcodebuild', '-version'], check=True)
    subprocess.run(['flutter', 'pub', 'get', '--enforce-lockfile'], cwd=APP, check=True)
    started = time.time_ns()
    subprocess.run(command, cwd=APP, check=True)
    # Flutter can finish archiving even if signing/export fails. Never copy an old IPA.
    candidates = [p for p in (APP / 'build/ios/ipa').glob('*.ipa') if p.stat().st_mtime_ns >= started]
    if len(candidates) != 1:
        raise ValueError('No unique freshly exported IPA was produced. Check Xcode signing/export errors. '
                         'No older artifact has been copied.')
    source = candidates[0]
    with tempfile.TemporaryDirectory(prefix='fray-ios-verify-') as temporary:
        subprocess.run(['ditto', '-x', '-k', str(source), temporary], check=True)
        apps = list((Path(temporary) / 'Payload').glob('*.app'))
        if len(apps) != 1 or not (apps[0] / 'embedded.mobileprovision').is_file():
            raise ValueError('The exported file does not contain a provisioned iPhone application.')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(apps[0])], check=True)
        with (apps[0] / 'Info.plist').open('rb') as file:
            info = plistlib.load(file)
    with source.open('rb') as file:
        digest = hashlib.file_digest(file, 'sha256').hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    # Unique directory preserves previous distributions and identifies their actual build version.
    directory = Path(tempfile.mkdtemp(prefix='fray-ios-', dir=output))
    target = directory / 'Fray.ipa'
    shutil.copy2(source, target)
    (directory / 'SHA256SUMS').write_text(digest + '  Fray.ipa\n')
    (directory / 'build.json').write_text(json.dumps({
        'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
        'bundleId': info['CFBundleIdentifier'], 'apiOrigin': args.api_url,
        'sha256': digest, 'distribution': 'custom export options' if args.export_options else args.method or 'app-store',
    }, indent=2) + '\n')
    print('Signed IPA copied outside the build folder: ' + str(target))
    print('App Store exports go to App Store Connect/TestFlight; ad hoc exports only install on registered devices.')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-only', action='store_true', help='Create a source ZIP, not an IPA; works on Linux')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/ios')
    parser.add_argument('--api-url', default='https://frayapi.klanija.com')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--method', choices=['app-store', 'ad-hoc', 'development'])
    group.add_argument('--export-options', type=Path, help='Use an ExportOptions.plist produced by Xcode')
    parser.add_argument('--build-number', type=lambda value: value if re.fullmatch(r'[1-9][0-9]*', value) else parser.error('Build number must be a positive integer'))
    args = parser.parse_args()
    try:
        if args.source_only:
            target = package_source(args.output.resolve())
            with target.open('rb') as file:
                digest = hashlib.file_digest(file, 'sha256').hexdigest()
            target.with_suffix('.zip.sha256').write_text(digest + '  ' + target.name + '\n')
        else:
            export_ipa(args, args.output.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as exc:
        parser.exit(1, f'{exc}\n')


if __name__ == '__main__':
    main()
