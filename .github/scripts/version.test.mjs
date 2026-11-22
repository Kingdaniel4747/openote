import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const workflow = readFileSync(new URL('../workflows/release.yml', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const body = workflow.split('      - name: Choose and validate the version')[1]
  .split('        run: |\n')[1].split('\n      - name:')[0]
  .split('\n').map(line => line.replace(/^          /, '')).join('\n');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';

function calculate(requested = '', tags = '', baseline = '0.8.0') {
  const fixture = mkdtempSync(join(tmpdir(), 'openote-version-'));
  try {
    mkdirSync(join(fixture, 'app'));
    writeFileSync(join(fixture, 'app/pubspec.yaml'), `version: ${baseline}+14\n`);
    const result = spawnSync(bash, ['-e', '-o', 'pipefail', '-c', `
      git() {
        if [[ "$1" == tag ]]; then printf '%s\\n' "$TEST_TAGS";
        elif [[ "$1" == rev-parse ]]; then
          printf '%s\\n' "$TEST_TAGS" | while IFS= read -r tag; do
            if [[ "refs/tags/$tag" == "$2" ]]; then exit 42; fi
          done
          [[ "$?" == 42 ]]
        else return 1; fi
      }
      ${body}
    `], { cwd: fixture, encoding: 'utf8', env: { ...process.env, REQUESTED_VERSION: requested,
      TEST_TAGS: tags, GITHUB_OUTPUT: 'version-output' } });
    assert.ifError(result.error);
    const output = join(fixture, 'version-output');
    return { status: result.status, error: result.stderr, output: existsSync(output) ? readFileSync(output, 'utf8') : '' };
  } finally { rmSync(fixture, { recursive: true, force: true }); }
}

test('first automatic release increments the pubspec baseline', () => {
  assert.deepEqual(calculate(), { status: 0, error: '', output: 'value=0.8.1\n' });
});
test('automatic release uses the highest public tag', () => {
  assert.equal(calculate('', 'v0.8.2\nv2.0.9\nv1.9.8').output, 'value=2.0.10\n');
});
test('manual versions work but duplicate or invalid tags never publish', () => {
  assert.equal(calculate('v3.2.1').output, 'value=3.2.1\n');
  for (const value of ['2.0.9', '01.2.3', '1.2', '65536.0.1', '1.2.65536', 'text']) {
    const result = calculate(value, 'v2.0.9');
    assert.notEqual(result.status, 0, value);
    assert.equal(result.output, '', value);
  }
});
test('patch exhaustion rolls into the next minor version', () => {
  assert.equal(calculate('', 'v1.2.65535').output, 'value=1.3.0\n');
  assert.equal(calculate('', 'v0.0.65535', '0.0.0').output, 'value=0.1.0\n');
  assert.equal(calculate('', 'v0.65535.65535').output, 'value=1.0.0\n');
});
