/* Progressive enhancement: all links remain usable if GitHub's API is unavailable. */
(async () => {
  const repository = 'Kingdaniel4747/openote';
  const english = document.documentElement.lang === 'en';
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return;
    const release = await response.json();
    if (release.draft || release.prerelease || !Array.isArray(release.assets)) return;
    const match = { windows: /^openote-[\d.]+-windows-x64-setup\.exe$/, android: /^openote-scanner-[\d.]+\.apk$/ };
    let resolved = 0;
    for (const [platform, pattern] of Object.entries(match)) {
      const asset = release.assets.find(item => pattern.test(item.name));
      if (!asset) continue;
      const url = new URL(asset.browser_download_url);
      if (url.protocol !== 'https:' || url.hostname !== 'github.com' ||
          !url.pathname.startsWith(`/${repository}/releases/download/`)) continue;
      for (const link of document.querySelectorAll(`[data-download="${platform}"]`)) {
        link.href = url.href;
      }
      resolved++;
    }
    if (resolved === 2 && typeof release.tag_name === 'string') {
      const status = document.getElementById('release-status');
      status.textContent = english
        ? `${release.tag_name} · Both download buttons now link directly to the latest packages on GitHub.`
        : `${release.tag_name} · Beide Download-Knöpfe führen direkt zu den aktuellen Installationsdateien auf GitHub.`;
    }
  } catch { /* Offline, rate-limited, old browser: keep the static release links. */ }
})();
