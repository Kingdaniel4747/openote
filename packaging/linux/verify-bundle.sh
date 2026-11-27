#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?Usage: verify-bundle.sh <bundle-dir>}"
bundle="$(cd "$bundle" && pwd)"
test -x "$bundle/openote"
test -s "$bundle/libonote_core.so"
test -s "$bundle/lib/libquickjs_c_bridge_plugin.so"
test -s "$bundle/lib/libpdfium.so"
video="$bundle/lib/libmedia_kit_video_plugin.so"
test -s "$video"
# The packages require libmpv2/mpv-libs. Never silently build against .so.1.
readelf -d "$video" | grep -F 'Shared library: [libmpv.so.2]'

while IFS= read -r -d '' binary; do
  # Dart's AOT library has no system dependencies. Check every ELF that does,
  # including libraries loaded lazily by PDF, video and JavaScript support.
  dynamic="$(readelf -d "$binary")"
  if [[ "$dynamic" == *'(NEEDED)'* ]]; then
    # Plugins share the engine already loaded by the executable. When checking
    # them separately, expose the bundled libraries explicitly to the loader.
    dependencies="$(LD_LIBRARY_PATH="$bundle/lib:$bundle" ldd "$binary")"
    if [[ "$dependencies" == *'not found'* ]]; then
      printf 'Unresolved dependencies in %s:\n%s\n' "$binary" "$dependencies" >&2
      exit 1
    fi
  fi
done < <(find "$bundle" -type f \( -name openote -o -name '*.so' -o -name '*.so.*' \) -print0)
