import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const script = readFileSync(new URL('../../website/downloads.js', import.meta.url), 'utf8');
const fallback = 'https://github.com/Kingdaniel4747/openote/releases/latest';
const prefix = 'https://github.com/Kingdaniel4747/openote/releases/download/v1.2.3/';
const extraAssets = ['openote-1.2.3-macos-universal.dmg', 'openote-1.2.3-linux-amd64.deb', 'openote-1.2.3-linux-x86_64.rpm'].map(name => ({ name, browser_download_url: prefix + name }));
const release = { tag_name: 'v1.2.3', assets: [
  { name: 'openote-1.2.3-windows-x64-setup.exe', browser_download_url: prefix + 'openote-1.2.3-windows-x64-setup.exe' },
  { name: 'openote-scanner-1.2.3.apk', browser_download_url: prefix + 'openote-scanner-1.2.3.apk' },
  ...extraAssets,
] };

async function simulate({ data = release, ok = true, offline = false, lang = 'en' } = {}) {
  const links = { windows: [{ href: fallback }, { href: fallback }], android: [{ href: fallback }], macos: [{ href: fallback }], 'linux-deb': [{ href: fallback }], 'linux-rpm': [{ href: fallback }] };
  const status = { textContent: 'fallback' };
  await runInNewContext(script, {
    URL, AbortSignal,
    fetch: async () => { if (offline) throw new Error('offline'); return { ok, json: async () => data }; },
    document: { documentElement: { lang }, getElementById: () => status,
      querySelectorAll: selector => links[selector.match(/data-download="([^"]+)"/)[1]] },
  });
  return { links, status };
}

test('all desktop and Android buttons resolve to the correct current assets', async () => {
  const { links, status } = await simulate();
  for (const link of links.windows) assert.equal(link.href, release.assets[0].browser_download_url);
  assert.equal(links.android[0].href, release.assets[1].browser_download_url);
  for (const [platform, asset] of [['macos', extraAssets[0]], ['linux-deb', extraAssets[1]], ['linux-rpm', extraAssets[2]]]) {
    assert.equal(links[platform][0].href, asset.browser_download_url);
  }
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

test('each missing platform asset preserves its fallback without mislabeling completeness', async () => {
  for (const platform of ['macos', 'linux-deb', 'linux-rpm']) {
    const name = { macos: extraAssets[0].name, 'linux-deb': extraAssets[1].name, 'linux-rpm': extraAssets[2].name }[platform];
    const { links, status } = await simulate({ data: { ...release, assets: release.assets.filter(asset => asset.name !== name) } });
    assert.equal(links[platform][0].href, fallback);
    assert.equal(links.windows[0].href, release.assets[0].browser_download_url);
    assert.equal(status.textContent, 'fallback');
  }
});

test('English version gets an English status without interpreting release HTML', async () => {
  const { status } = await simulate({ lang: 'en', data: { ...release, tag_name: '<b>v1.2.3</b>' } });
  assert.match(status.textContent, /All download buttons/);
  assert.match(status.textContent, /<b>v1.2.3<\/b>/);
});

test('download status stays English even with a German language setting', async () => {
  const { status } = await simulate({ lang: 'de' });
  assert.match(status.textContent, /All download buttons/);
});
