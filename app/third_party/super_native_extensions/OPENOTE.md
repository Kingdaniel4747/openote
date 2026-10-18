# Openote Windows path-resolution patch

Source: published [super_native_extensions 0.9.1](https://pub.dev/packages/super_native_extensions/versions/0.9.1).
Original pub archive SHA-256:
`b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569`.
MIT licence retained. All runtime sources and supported platform implementations
are retained; upstream tests and analyzer configuration are omitted.

The only runtime/build-source change is in
`cargokit/cmake/resolve_symlinks.ps1`: use
`Get-Item -LiteralPath $realPath -Force -ErrorAction Stop`.
`-Force` permits hidden path components such as a default Windows AppData
directory, `-LiteralPath` handles brackets as literal filenames, and terminating
errors prevent continuing with an invalid path. This does not change filesystem
permissions. The native clipboard/Rust code and Cargokit downloads are unchanged.

The relative local path override keeps this fix reproducible without editing
the global Pub cache. Remove it when the resolver fix is available upstream.
