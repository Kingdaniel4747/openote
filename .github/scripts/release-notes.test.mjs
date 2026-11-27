import test from 'node:test';
import assert from 'node:assert/strict';
import { buildReleaseNotes, extractNotes } from './release-notes.mjs';

const section = text => `# Aufgaben\n<!-- release-notes:start -->\n${text}\n<!-- release-notes:end -->\n## Private Arbeit\nNicht veröffentlichen`;
const base = { version: '0.9.1', date: '2026-11-22', commits: '- PDF-Zoom verbessert (abc123)' };

test('publishes only marked user notes, with date, commits and all three packages', () => {
  const result = buildReleaseNotes({ ...base, tasks: section('- **Neu:** Scharfe PDFs') });
  assert.match(result, /\*\*Neu:\*\* Scharfe PDFs/);
  assert.match(result, /2026-11-22/);
  assert.match(result, /windows-x64-setup\.exe/);
  assert.match(result, /openote-scanner-0\.9\.1\.apk/);
  assert.match(result, /openote-0\.9\.1-macos-universal\.dmg/);
  assert.match(result, /ohne Apple-Notarisierung/);
  assert.match(result, /PDF-Zoom verbessert \(abc123\)/);
  assert.doesNotMatch(result, /Private Arbeit|Nicht veröffentlichen|release-notes:start/);
});

test('does not present unchanged feature notes as new on another push', () => {
  const tasks = section('- Bereits veröffentlicht');
  const result = buildReleaseNotes({ ...base, tasks, previousTasks: tasks });
  assert.match(result, /Wartungsupdate/);
  assert.doesNotMatch(result, /Bereits veröffentlicht/);
  assert.match(result, /PDF-Zoom verbessert/);
});

test('takes new notes even when unrelated task text stays the same', () => {
  const result = buildReleaseNotes({ ...base, tasks: section('- Neu'), previousTasks: section('- Alt') });
  assert.match(result, /- Neu/);
  assert.doesNotMatch(result, /- Alt/);
});

test('explicit manual notes override the TASKS summary as literal Markdown', () => {
  const override = '- Manuell: `$(echo test)` und **Markdown**';
  const result = buildReleaseNotes({ ...base, tasks: section('- Automatisch'), override });
  assert.ok(result.includes(override));
  assert.doesNotMatch(result, /- Automatisch/);
});

test('missing, empty or incomplete markers give useful maintenance notes', () => {
  for (const tasks of ['', '# Aufgaben', '<!-- release-notes:start -->\nGeheime Aufgabe', section('')]) {
    assert.equal(extractNotes(tasks), '');
    const result = buildReleaseNotes({ ...base, tasks });
    assert.match(result, /Wartungsupdate/);
    assert.doesNotMatch(result, /Geheime Aufgabe/);
  }
});

test('normalizes CRLF and whitespace around a marked section', () => {
  assert.equal(extractNotes(section('  - Neu  ').replaceAll('\n', '\r\n')), '- Neu');
  const tasks = section('- Schon veröffentlicht\n- Zweiter Punkt');
  const result = buildReleaseNotes({ ...base, tasks: tasks.replaceAll('\n', '\r\n'), previousTasks: tasks });
  assert.match(result, /Wartungsupdate/);
  assert.doesNotMatch(result, /Schon veröffentlicht/);
});
