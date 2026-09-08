# Releasing Openote

Openote ships two packages from one GitHub release:

| Package | File |
|---|---|
| Windows desktop app | `openote-X.Y.Z-windows-x64-setup.exe` |
| Android Scanner | `openote-scanner-X.Y.Z.apk` |

Normale Pushes starten keinen automatischen Test- oder Paketlauf.
`Release packages` läuft nur für einen `vX.Y.Z`-Tag oder bei manuellem Start
mit einer Version.

## One-time Android signing setup

Android accepts an update only when every APK uses the same signing certificate.
Create a release keystore once, store it securely outside the repository, and
add these GitHub Actions repository secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the complete `.jks` keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

The `.jks` file and `scanner/android/key.properties` are ignored deliberately.
Never put either into a commit. The release build fails if one secret is absent;
that is safer than publishing an APK which Android cannot update later.

On Windows, one possible setup is:

```powershell
keytool -genkeypair -v -keystore openote-release.jks -alias openote -keyalg RSA -keysize 4096 -validity 10000
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes(".\openote-release.jks"))
```

Store the Base64 output and passwords only as GitHub secrets, and keep an
encrypted offline backup of the keystore.

## Normal release

1. Choose the next unused version, for example `0.8.33`.
2. Create and push the matching tag:

   ```powershell
   git tag v0.8.33
   git push origin v0.8.33
   ```

3. Wait for `Release packages`. Windows installer and APK build in parallel;
   the final job checks that both non-empty files exist.
4. Open the resulting draft in GitHub **Releases**. Confirm the version, notes,
   EXE, and APK, then publish it.

For a rebuild of a selected branch commit, start **Actions → Release packages →
Run workflow** and enter an unused `X.Y.Z` version. Do not reuse a published
version or overwrite an existing release.

## Local builds

Windows desktop app:

```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

The CMake project builds `rust/onote_core` and places `onote_core.dll` next to
the executable. To create the installer after that build, use Inno Setup 6 and:

```powershell
.\packaging\windows\build-installer.ps1 -Version 0.8.33
```

For a local release APK, create `scanner/android/key.properties` pointing to
your private keystore, then run:

```powershell
cd scanner
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Failure guide

| Symptom | Action |
|---|---|
| APK job reports missing signing secrets | Add all four `ANDROID_*` secrets; do not replace the keystore after any release. |
| Windows packaging says `onote_core.dll` is missing | Ensure Rust is available and rerun `flutter build windows --release`; the installer deliberately rejects the pure-Dart fallback. |
| Draft has only one package | Do not publish it. Inspect the failed parallel job and create a new version after fixing it. |
| Installed scanner will not update | Compare its signing certificate with the release keystore. A different certificate requires a one-time uninstall and reinstall. |
