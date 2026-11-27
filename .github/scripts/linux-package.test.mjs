import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, cpSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';

const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const packaging = new URL('../../packaging/linux/', import.meta.url);

function fixture(run) {
  const dir = mkdtempSync(join(tmpdir(), 'openote-linux-'));
  try {
    cpSync(packaging, join(dir, 'packaging/linux'), { recursive: true });
    mkdirSync(join(dir, 'app/assets/icon'), { recursive: true });
    writeFileSync(join(dir, 'app/assets/icon/openote_icon.png'), 'test icon');
    writeFileSync(join(dir, 'LICENSE'), 'test license');
    mkdirSync(join(dir, 'bundle/lib'), { recursive: true });
    writeFileSync(join(dir, 'bundle/openote'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    writeFileSync(join(dir, 'bundle/libonote_core.so'), 'test importer');
    writeFileSync(join(dir, 'bundle/lib/libmedia_kit_video_plugin.so'), 'test video');
    writeFileSync(join(dir, 'bundle/lib/libpdfium.so'), 'test PDF');
    writeFileSync(join(dir, 'bundle/lib/libquickjs_c_bridge_plugin.so'), 'test JavaScript');
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function verify(dir, failure = '') {
  return spawnSync(bash, ['-e', '-o', 'pipefail', '-c', `
    readelf() {
      test -s "$2" || return 1
      [[ "$TEST_FAILURE" != invalid ]] || return 1
      if [[ "$2" == *libmedia_kit_video_plugin.so ]]; then
        if [[ "$TEST_FAILURE" == abi ]]; then
          echo ' (NEEDED) Shared library: [libmpv.so.1]'
        else
          echo ' (NEEDED) Shared library: [libmpv.so.2]'
        fi
      else
        echo ' (NEEDED) Shared library: [libc.so.6]'
      fi
    }
    ldd() {
      [[ "$LD_LIBRARY_PATH" == */bundle/lib:*/bundle ]] || return 1
      if [[ "$TEST_FAILURE" == missing && "$1" == *libpdfium.so ]]; then
        echo 'libfreetype.so.6 => not found'
      elif [[ "$TEST_FAILURE" == loader ]]; then
        return 1
      else
        echo 'libc.so.6 => /lib/libc.so.6'
      fi
    }
    source packaging/linux/verify-bundle.sh bundle
  `], { cwd: dir, encoding: 'utf8', env: { ...process.env, TEST_FAILURE: failure } });
}

test('bundle verification accepts resolved libraries with the packaged MPV ABI', () => {
  fixture(dir => assert.equal(verify(dir).status, 0));
});

test('bundle verification rejects the wrong MPV ABI, missing PDF libraries and loader errors', () => {
  fixture(dir => {
    for (const failure of ['abi', 'missing', 'loader', 'invalid']) {
      assert.notEqual(verify(dir, failure).status, 0, failure);
    }
    for (const library of ['libonote_core.so', 'lib/libquickjs_c_bridge_plugin.so', 'lib/libpdfium.so']) {
      const path = join(dir, 'bundle', library);
      const contents = readFileSync(path);
      rmSync(path);
      assert.notEqual(verify(dir).status, 0, library);
      writeFileSync(path, contents);
    }
  });
});

test('invalid package versions fail before any package builder is invoked', () => {
  fixture(dir => {
    const result = spawnSync(bash, ['packaging/linux/build-packages.sh', '../bad', 'bundle'],
      { cwd: dir, encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Version must be X.Y.Z/);
  });
});

test('real DEB and RPM include the launcher, icon, MIME types and native importer',
  { skip: process.platform !== 'linux' || process.env.OPENOTE_LINUX_PACKAGE_TESTS !== '1' }, () => {
    fixture(dir => {
      const result = spawnSync(bash, ['packaging/linux/build-packages.sh', '1.2.3', 'bundle', 'out'],
        { cwd: dir, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stdout + result.stderr);
      const deb = join(dir, 'out/openote-1.2.3-linux-amd64.deb');
      const rpm = join(dir, 'out/openote-1.2.3-linux-x86_64.rpm');
      const command = (tool, args) => execFileSync(tool, args, { encoding: 'utf8' });
      const debFiles = command('dpkg-deb', ['--contents', deb]);
      const rpmFiles = command('rpm', ['--query', '--package', '--list', rpm]);
      for (const path of ['/opt/openote/openote', '/opt/openote/libonote_core.so',
        '/opt/openote/lib/libquickjs_c_bridge_plugin.so',
        '/usr/bin/openote', '/usr/share/applications/org.openote.openote.desktop',
        '/usr/share/icons/hicolor/512x512/apps/openote.png', '/usr/share/mime/packages/openote.xml']) {
        assert.ok(debFiles.includes(path), path);
        assert.ok(rpmFiles.includes(path), path);
      }
      assert.doesNotMatch(rpmFiles, /\/DEBIAN\//);
      assert.match(command('dpkg-deb', ['--field', deb, 'Depends']), /libmpv2/);
      assert.match(command('rpm', ['--query', '--package', '--requires', rpm]), /libmpv\.so\.2/);
      command('dpkg-deb', ['--extract', deb, join(dir, 'extracted')]);
      assert.equal(readFileSync(join(dir, 'extracted/opt/openote/libonote_core.so'), 'utf8'), 'test importer');
    });
  });
