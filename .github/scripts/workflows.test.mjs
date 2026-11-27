import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const directory = new URL('../workflows/', import.meta.url);
const read = name => readFileSync(new URL(name, directory), 'utf8');
const main = read('release.yml');

test('pushes never start a build, release or website deployment', () => {
  for (const name of readdirSync(directory).filter(name => name.endsWith('.yml'))) {
    const workflow = read(name);
    assert.doesNotMatch(workflow, /^\s+(push|pull_request|schedule|workflow_run):/m, name);
    assert.match(workflow, /^  workflow_dispatch:/m, name);
  }
});

test('manual platform builds upload artifacts and the main release reuses them', () => {
  for (const platform of ['windows', 'macos', 'linux']) {
    const workflow = read(`build-${platform}.yml`);
    assert.match(workflow, /^  workflow_call:/m);
    assert.ok(main.includes(`uses: ./.github/workflows/build-${platform}.yml`));
    assert.ok(workflow.includes(`name: release-${platform}`));
    assert.match(workflow, /uses: actions\/upload-artifact@/);
    assert.doesNotMatch(workflow, /action-gh-release|contents: write/);
    assert.ok(workflow.indexOf('Validate build version') < workflow.indexOf('run: flutter pub get'));
  }
  assert.match(main, /needs: \[version, windows, macos, linux, android\]/);
  assert.match(main, /uses: softprops\/action-gh-release@/);
});

test('standalone build versions reject malformed input and accept supported Windows components', () => {
  const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
  for (const version of ['0.8.0', '65535.0.1', '1.2', '1.02.3', '65536.0.0', '$(echo injected)', '']) {
    const result = spawnSync(bash, ['.github/scripts/validate-build-version.sh'],
      { env: { ...process.env, BUILD_VERSION: version }, encoding: 'utf8' });
    assert.ifError(result.error);
    assert.equal(result.status === 0, ['0.8.0', '65535.0.1'].includes(version), version);
  }
});
