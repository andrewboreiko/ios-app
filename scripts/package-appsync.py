#!/usr/bin/env python3
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build' / 'appsync'
XCODE = Path(os.environ.get('XCODE_PATH', '/Applications/Xcode.app'))
ENV = {**os.environ, 'DEVELOPER_DIR': str(XCODE / 'Contents' / 'Developer')}
BUNDLE_ID = os.environ.get('BUNDLE_ID', 'com.andrewboreiko.hadashboard.dev')


def run(*args, capture=False):
    result = subprocess.run([str(arg) for arg in args], cwd=ROOT, env=ENV,
                            check=True, text=True, capture_output=capture)
    return result.stdout.strip() if capture else None


def validate_binary(binary):
    assert run('xcrun', 'lipo', '-archs', binary, capture=True) == 'armv7 arm64'
    for arch in ['armv7', 'arm64']:
        commands = run('xcrun', 'otool', '-l', '-arch', arch, binary, capture=True)
        assert re.search(r'cmd LC_VERSION_MIN_IPHONEOS\s+cmdsize \d+\s+version 9\.0\s', commands)


def make_template(version, build):
    log = OUTPUT / 'template-build.log'
    args = ['xcodebuild', '-project', 'HADashboard.xcodeproj', '-scheme', 'HADashboard',
            '-sdk', 'iphoneos', '-configuration', 'Release', '-derivedDataPath', str(OUTPUT / 'template'),
            'ARCHS=arm64', 'VALID_ARCHS=arm64', 'ONLY_ACTIVE_ARCH=NO',
            'IPHONEOS_DEPLOYMENT_TARGET=15.0', f'PRODUCT_BUNDLE_IDENTIFIER={BUNDLE_ID}',
            f'MARKETING_VERSION={version}', f'CURRENT_PROJECT_VERSION={build}',
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=',
            'DEVELOPMENT_TEAM=', 'build']
    with log.open('w') as stream:
        result = subprocess.run(args, cwd=ROOT, env=ENV, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'Unsigned resource template failed; inspect {log}')
    return OUTPUT / 'template/Build/Products/Release-iphoneos/HA Dashboard.app'


def prepare_bundle(template, binary, version, build):
    payload = OUTPUT / 'Payload'
    if payload.exists():
        shutil.rmtree(payload)
    payload.mkdir()
    app = payload / 'HA Dashboard Dev.app'
    shutil.copytree(template, app, symlinks=True)
    for name in ['_CodeSignature', 'embedded.mobileprovision']:
        item = app / name
        if item.is_dir():
            shutil.rmtree(item)
        elif item.exists():
            item.unlink()
    shutil.copy2(binary, app / 'HA Dashboard')
    run('xcrun', 'ibtool', '--compile', app / 'LaunchScreen.storyboardc',
        ROOT / 'HADashboard/LaunchScreen.storyboard', '--minimum-deployment-target', '9.0',
        '--target-device', 'ipad', '--target-device', 'iphone')
    info_path = app / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleDisplayName='HA Dashboard Dev',
                CFBundleShortVersionString=version, CFBundleVersion=build,
                MinimumOSVersion='9.0', UIRequiredDeviceCapabilities=['armv7'],
                UILaunchStoryboardName='LaunchScreen')
    info.pop('UILaunchScreen', None)
    ipad_icons = info.setdefault('CFBundleIcons~ipad', {}).setdefault('CFBundlePrimaryIcon', {})
    ipad_icons['CFBundleIconFiles'] = ['AppIcon60x60', 'AppIcon76x76', 'AppIcon83.5x83.5']
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    icon = ROOT / 'HADashboard/Assets.xcassets/AppIcon.appiconset/icon-1024.png'
    for size, name in [(76, 'AppIcon76x76~ipad.png'), (152, 'AppIcon76x76@2x~ipad.png'),
                       (167, 'AppIcon83.5x83.5@2x~ipad.png'), (120, 'AppIcon60x60@2x.png'),
                       (180, 'AppIcon60x60@3x.png')]:
        run('sips', '-z', size, size, icon, '--out', app / name, capture=True)
    return app


def sign_bundle(app):
    entitlements = OUTPUT / 'appsync-entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({
        'application-identifier': BUNDLE_ID,
        'keychain-access-groups': [BUNDLE_ID],
    }))
    run('codesign', '--force', '--sign', '-', '--identifier', BUNDLE_ID,
        '--entitlements', entitlements, '--timestamp=none', app)
    run('codesign', '--verify', '--deep', '--strict', app)


def package_bundle(app, version, build):
    validate_binary(app / 'HA Dashboard')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == BUNDLE_ID
    assert info['MinimumOSVersion'] == '9.0'
    for resource in ['PrivacyInfo.xcprivacy', 'materialdesignicons-webfont.ttf',
                     'mdi-codepoints.tsv', 'en.lproj/Localizable.strings', 'LaunchScreen.storyboardc']:
        assert (app / resource).exists(), resource
    ipa = OUTPUT / f'HA-Dashboard-Dev-{version}-{build}-appsync.ipa'
    with zipfile.ZipFile(ipa, 'w', zipfile.ZIP_DEFLATED) as archive:
        for entry in sorted(app.rglob('*')):
            if entry.is_file():
                archive.write(entry, entry.relative_to(OUTPUT))
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None
        assert all(name.startswith('Payload/HA Dashboard Dev.app/') for name in archive.namelist())
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    ipa.with_suffix('.ipa.sha256').write_text(f'{digest}  {ipa.name}\n')
    source_hash = hashlib.sha256()
    for source in sorted(p for folder in ['HADashboard', 'Vendor'] for p in (ROOT / folder).rglob('*') if p.suffix in ['.m', '.h']):
        source_hash.update(str(source.relative_to(ROOT)).encode() + b'\0' + source.read_bytes())
    metadata = {'file': str(ipa), 'sha256': digest, 'bundleId': BUNDLE_ID,
                'appSourcesSha256': source_hash.hexdigest(),
                'version': version, 'build': build, 'architectures': ['armv7', 'arm64'],
                'minimumOSVersion': '9.0', 'signing': 'ad-hoc for AppSync',
                'commit': run('git', 'rev-parse', 'HEAD', capture=True), 'deviceTested': False}
    (OUTPUT / 'build-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))


def main():
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', BUNDLE_ID) or BUNDLE_ID == 'com.hadashboard.app':
        raise ValueError('A separate valid test Bundle ID is required')
    binary = ROOT / 'build/universal/universal-thin'
    if not binary.exists():
        raise RuntimeError('Build baseline slices with HADASHBOARD_SLICES_ONLY=YES first')
    sources = [p for folder in ['HADashboard', 'Vendor'] for p in (ROOT / folder).rglob('*')
               if p.suffix in ['.m', '.h']]
    if any(p.stat().st_mtime > binary.stat().st_mtime for p in sources):
        raise RuntimeError('Sources are newer than baseline slices; rebuild them first')
    validate_binary(binary)
    version = run('git', 'describe', '--tags', '--abbrev=0', '--match', 'v*', capture=True).removeprefix('v')
    build = os.environ.get('HADASHBOARD_BUILD_NUMBER') or run('git', 'rev-list', '--count', 'HEAD', capture=True)
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', build):
        raise ValueError('Build number must contain one to three numeric components')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    template = make_template(version, build)
    app = prepare_bundle(template, binary, version, build)
    sign_bundle(app)
    package_bundle(app, version, build)


if __name__ == '__main__':
    main()
