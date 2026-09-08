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

Every pushed change starts the Release workflow. It builds Windows and Android
independently, calculates the next patch version, then publishes one GitHub
release containing both files.

Android updates must keep the same signing certificate forever. Before the first
release, create one keystore and add these repository secrets in GitHub Actions:

- `ANDROID_KEYSTORE_BASE64` â€” Base64 content of the `.jks` file.
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The workflow writes these values only on the ephemeral build runner. Never commit
`key.properties` or a `.jks` file. A release fails intentionally when a secret is
missing; silently falling back to a debug key would break all future APK updates.

On Windows, create the keystore once with Java's `keytool`, keep an encrypted
offline backup, and store the printed passwords separately:

```powershell
keytool -genkeypair -v -keystore openote-release.jks -alias openote -keyalg RSA -keysize 4096 -validity 10000
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes(".\openote-release.jks"))
```

Use the Base64 output for `ANDROID_KEYSTORE_BASE64`, `openote` for
`ANDROID_KEY_ALIAS`, and the two passwords for the remaining secrets.
