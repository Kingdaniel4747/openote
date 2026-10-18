# Openote compatibility patch

Source: published [pdfrx_engine 0.3.9](https://pub.dev/packages/pdfrx_engine/versions/0.3.9).
Published archive SHA-256 (original hosted lockfile entry):
`a8914433d1f6188b903c53d36b9d7dc908bfa89131591a9db22f1a22470d3a48`.
MIT licence retained. Runtime lib/, package manifest and upstream documentation
are included; upstream example/tests and development-only dependencies are omitted.
Removed `resolution: workspace` because this is a standalone path dependency.

In `pdfDocumentFromUri`, bind `cache ?? await PdfFileCache.fromUri(uri)` to a
final non-null `resolvedCache` and use it throughout the function. This avoids
relying on nullable parameter promotion across the async read callback, where
Dart 3.13.5 rejects `cache.blockSize` and `cache.read` after an await.
It also removes the now-unnecessary null assertions. No download, cache,
disposal, password, rendering, editing, or public API behavior is changed.

The same non-null local binding approach is used by
[current upstream](https://github.com/espresso3389/pdfrx/blob/master/packages/pdfrx_engine/lib/src/native/pdf_file_cache.dart).
The first published fixed line is 0.4.x; using it requires changing the existing
pdfrx 2.2.24 / pdfium_flutter 0.1.9 / pdfium_dart 0.1.x dependency set and PDFium
packaging. This backport keeps that migration out of the Windows startup fix.
Remove the override when that coordinated PDF dependency update is performed.

Workspace diagnostic cleanup also adds `await` to the three native document
creation returns inside try/catch/finally in `pdfrx_pdfium.dart`. This ensures
errors reach cleanup and JPEG memory stays alive until asynchronous creation
completes. The constant line threshold in `pdf_text_formatter.dart` is declared
`const`. These changes address the analyzer findings without changing APIs.
