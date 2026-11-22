import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const script = readFileSync(new URL('../../website/downloads.js', import.meta.url), 'utf8');
const fallback = 'https://github.com/Kingdaniel4747/openote/releases/latest';
const prefix = 'https://github.com/Kingdaniel4747/openote/releases/download/v1.2.3/';
const release = { tag_name: 'v1.2.3', assets: [
  { name: 'openote-1.2.3-windows-x64-setup.exe', browser_download_url: prefix + 'openote-1.2.3-windows-x64-setup.exe' },
  { name: 'openote-scanner-1.2.3.apk', browser_download_url: prefix + 'openote-scanner-1.2.3.apk' },
] };

async function simulate({ data = release, ok = true, offline = false, lang = 'de' } = {}) {
  const links = { windows: [{ href: fallback }, { href: fallback }], android: [{ href: fallback }] };
  const status = { textContent: 'fallback' };
  await runInNewContext(script, {
    URL, AbortSignal,
    fetch: async () => { if (offline) throw new Error('offline'); return { ok, json: async () => data }; },
    document: { documentElement: { lang }, getElementById: () => status,
      querySelectorAll: selector => links[selector.includes('windows') ? 'windows' : 'android'] },
  });
  return { links, status };
}

test('all Windows and Android buttons resolve to the correct current assets', async () => {
  const { links, status } = await simulate();
  for (const link of links.windows) assert.equal(link.href, release.assets[0].browser_download_url);
  assert.equal(links.android[0].href, release.assets[1].browser_download_url);
  assert.match(status.textContent, /v1.2.3/);
});

test('offline, API limits, missing assets and prereleases preserve usable links', async () => {
  for (const scenario of [{ offline: true }, { ok: false }, { data: {} }, { data: { ...release, assets: [] } },
    { data: { ...release, prerelease: true } }, { data: { ...release, draft: true } }]) {
    const { links, status } = await simulate(scenario);
    assert.equal(links.windows[0].href, fallback);
    assert.equal(links.android[0].href, fallback);
    assert.equal(status.textContent, 'fallback');
  }
});

test('a missing Android asset does not break the Windows download or mislabel availability', async () => {
  const { links, status } = await simulate({ data: { ...release, assets: [release.assets[0]] } });
  assert.equal(links.windows[0].href, release.assets[0].browser_download_url);
  assert.equal(links.android[0].href, fallback);
  assert.equal(status.textContent, 'fallback');
});

test('never replaces download links with an unexpected host, scheme or repository', async () => {
  for (const url of ['https://example.com/app.exe', 'javascript:alert(1)',
    'http://github.com/Kingdaniel4747/openote/releases/download/file',
    'https://github.com/someone/another/releases/download/file']) {
    const { links } = await simulate({ data: { ...release, assets: [{ ...release.assets[0], browser_download_url: url }] } });
    assert.equal(links.windows[0].href, fallback);
  }
});

test('English version gets an English status without interpreting release HTML', async () => {
  const { status } = await simulate({ lang: 'en', data: { ...release, tag_name: '<b>v1.2.3</b>' } });
  assert.match(status.textContent, /Both download buttons/);
  assert.match(status.textContent, /<b>v1.2.3<\/b>/);
});
