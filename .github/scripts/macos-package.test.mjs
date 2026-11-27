import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const script = readFileSync(new URL('../../packaging/macos/build-dmg.sh', import.meta.url), 'utf8');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';

// Exercise the real packaging shell with stand-ins for Apple's macOS-only tools.
// The first Mac CI build still validates the actual Mach-O files and signatures.
function packageApp({ missingCore = false, failure = '', version = '1.2.3' } = {}) {
  const fixture = mkdtempSync(join(tmpdir(), 'openote-macos-'));
  try {
    const app = 'app/build/macos/Build/Products/Release/Openote.app';
    mkdirSync(join(fixture, app, 'Contents/MacOS'), { recursive: true });
    writeFileSync(join(fixture, app, 'Contents/MacOS/Openote'), 'app');
    for (const arch of ['aarch64', 'x86_64']) {
      const dir = `rust/onote_core/target/${arch}-apple-darwin/release`;
      mkdirSync(join(fixture, dir), { recursive: true });
      if (!(missingCore && arch === 'x86_64')) {
        writeFileSync(join(fixture, dir, 'libonote_core.dylib'), arch);
      }
    }
    writeFileSync(join(fixture, 'package.sh'), script);
    const result = spawnSync(bash, ['-e', '-o', 'pipefail', '-c', `
      lipo() {
        if [[ "$1" == -create ]]; then
          test -s "$2" && test -s "$3" || return 1
          cat "$2" "$3" > "$5"
        else
          test -s "$1" || return 1
          [[ "$#" == 4 && "$2" == -verify_arch && "$3" == arm64 && "$4" == x86_64 ]] || return 1
          [[ "$TEST_FAILURE" != architecture ]]
        fi
      }
      codesign() { [[ "$TEST_FAILURE" != signing ]]; }
      ditto() { cp -R "$1" "$2"; }
      # Git Bash cannot create a dangling /Applications symlink on Windows.
      ln() { [[ "$1" == -s ]] && printf '%s' "$2" > "$3"; }
      hdiutil() {
        if [[ "$1" == create ]]; then
          test -s "$5/Openote.app/Contents/MacOS/libonote_core.dylib" || return 1
          [[ "$(cat "$5/Applications")" == /Applications ]] || return 1
          touch "$9"
        else
          [[ "$TEST_FAILURE" != image ]]
        fi
      }
      source ./package.sh "$TEST_VERSION"
    `], { cwd: fixture, encoding: 'utf8', env: { ...process.env,
      TEST_FAILURE: failure, TEST_VERSION: version } });
    assert.ifError(result.error);
    return { status: result.status, error: result.stderr,
      dmg: existsSync(join(fixture, 'openote-1.2.3-macos-universal.dmg')) };
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
}

test('DMG stages the app, both importer architectures and Applications link', () => {
  assert.deepEqual(packageApp(), { status: 0, error: '', dmg: true });
});

test('missing importer target, thin app or failed signing stop packaging', () => {
  for (const options of [{ missingCore: true }, { failure: 'architecture' }, { failure: 'signing' }]) {
    const result = packageApp(options);
    assert.notEqual(result.status, 0, JSON.stringify(options));
    assert.equal(result.dmg, false, JSON.stringify(options));
  }
});

test('invalid versions and corrupt disk images fail the packaging step', () => {
  assert.notEqual(packageApp({ version: '../bad' }).status, 0);
  assert.notEqual(packageApp({ failure: 'image' }).status, 0);
});
