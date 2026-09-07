# Openote Scanner

The Android companion scans paper directly into a selected Openote page. It
does not open, download or expose notebooks.

## Use

1. Open the destination page in Openote on the computer.
2. Choose **Scan from phone** in the top bar.
3. Open Openote Scanner on Android. Its camera starts immediately; scan the
   displayed QR code.
4. The document scanner opens automatically. Scan up to 20 sheets. Each sheet
   is cropped and enhanced by Android, then placed in one aligned vertical
   stack on the selected page. The pairing dialog closes after the last page.

Both devices must be on the same Wi-Fi network. The Windows firewall may ask
whether Openote can receive connections; allow private networks. Closing the
pairing dialog immediately stops the receiver and invalidates its random key.

At startup the scanner first performs a short update check. If a newer scanner
APK exists in the latest GitHub release, it offers to download it and opens the
normal Android installation confirmation. If no update is available (or the
phone is offline), the QR camera opens immediately.

## GitHub build

The Release workflow builds Windows and Android independently and in parallel.
A short third job then publishes one GitHub release containing both the Windows
installer and the versioned `openote-scanner-<version>.apk`. The `Android
Scanner APK` workflow remains available as a manual APK-only development build.
