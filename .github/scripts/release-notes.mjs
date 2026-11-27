import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const start = '<!-- release-notes:start -->';
const end = '<!-- release-notes:end -->';

export function extractNotes(text) {
  const from = text.indexOf(start);
  const to = text.indexOf(end, from + start.length);
  if (from < 0 || to < 0) return '';
  return text.slice(from + start.length, to).replaceAll('\r\n', '\n').trim();
}

export function buildReleaseNotes({ tasks, previousTasks = '', override = '', commits = '', version, date }) {
  const current = extractNotes(tasks);
  const edited = current && current !== extractNotes(previousTasks);
  const summary = override.trim() || (edited ? current :
    '- Wartungsupdate: Die seit der letzten Version übernommenen Änderungen stehen unten.');
  return `## Neu in Openote ${version}\n\nVeröffentlicht am ${date}. Windows-App, macOS-App und Android-Scanner gehören zu dieser Version.\n\n${summary}\n\n## Downloads und Updates\n\n- Windows: die Datei mit \`windows-x64-setup.exe\` herunterladen und ausführen.\n- macOS (Intel und Apple Silicon, ab macOS 12): \`openote-${version}-macos-universal.dmg\` öffnen und Openote in Programme ziehen. Nur ad-hoc signiert, ohne Apple-Notarisierung; bei Bedarf nach dem ersten Startversuch in Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen freigeben. Updates durch Beenden und Ersetzen der App installieren.\n- Android: die Datei \`openote-scanner-${version}.apk\` auf dem Handy installieren.\n- Bestehende Installationen zeigen verfügbare Updates in der App an. Die Installation wird bestätigt; Android benötigt weiterhin denselben Signaturschlüssel.\n\n## Änderungen im Quellcode\n\n${commits.trim() || '- Erster gemeinsamer Paketstand.'}\n`;
}

export function writeReleaseNotes() {
  const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
  // Only real public-version tags on this commit's history form the baseline.
  const tags = git('tag', '--merged', 'HEAD', '--sort=-version:refname')
    .split('\n').filter(tag => /^v\d+\.\d+\.\d+$/.test(tag));
  const previous = tags[0];
  let previousTasks = '';
  if (previous) {
    try { previousTasks = git('show', `${previous}:TASKS.md`); } catch { /* Older releases may predate TASKS.md. */ }
  }
  const commits = git('log', '--no-merges', '--format=- %s (%h)',
    ...(previous ? [`${previous}..HEAD`] : ['-20', 'HEAD']));
  writeFileSync('release-body.md', buildReleaseNotes({
    tasks: readFileSync('TASKS.md', 'utf8'), previousTasks, commits,
    override: process.env.RELEASE_NOTES_OVERRIDE || '',
    version: process.env.RELEASE_VERSION,
    date: new Date().toISOString().slice(0, 10),
  }));
}
