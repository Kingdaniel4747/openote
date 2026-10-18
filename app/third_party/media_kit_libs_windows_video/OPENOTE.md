# Openote Windows build patch

Source: https://github.com/media-kit/media-kit/tree/c533e446755f51cf53c7e57aea873f2aa5355f81/libs/windows/media_kit_libs_windows_video

Version: 1.0.12, MIT; upstream LICENSE retained. Only the package manifest,
documentation, licence and Windows implementation are vendored. No binaries.

Changes from that immutable upstream commit:

- Add the missing `POST_BUILD` to ANGLE's CMake-tar extraction command.
  With `CMP0175 NEW`, CMake 3.31+ rejects the original TARGET command.
- Guard `CMP0175` with `if(POLICY CMP0175)` so older CMake versions supported
  by the package's 3.14 minimum can still configure it.
- Remove `resolution: workspace` from pubspec.yaml: this package now lives
  outside the upstream Dart workspace and is a standalone path dependency.

The MPV/ANGLE URLs, checksums, native registration, mutex compatibility
definition and bundled DLL list are unchanged. No other plugin is overridden.
Remove this local override once an upstream package includes these fixes and
the working MPV archive; check both extraction paths before switching back.
