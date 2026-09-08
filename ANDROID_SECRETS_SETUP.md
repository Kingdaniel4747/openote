# Android-APK: GitHub-Secrets einrichten

Diese Schritte einmal durchführen, bevor der nächste Android-Scanner-Release
gestartet wird. Die vier Werte werden in GitHub unter
**Repository → Settings → Secrets and variables → Actions → New repository secret**
eingegeben.

## 1. Keystore einmal erzeugen

PowerShell im gewünschten sicheren Ordner öffnen und ausführen:

```powershell
keytool -genkeypair -v -keystore openote-release.jks -alias openote -keyalg RSA -keysize 4096 -validity 10000
```

Bei den Fragen einen starken Keystore-/Key-Passwort festlegen und sicher
außerhalb des Projekts speichern. Für das Key-Passwort kann dasselbe Passwort
wie für den Keystore verwendet werden. Die Datei `openote-release.jks` danach
an einem sicheren, verschlüsselten Ort sichern; niemals in dieses Projekt legen
oder hochladen.

## 2. Base64-Wert erzeugen

Im selben Ordner ausführen:

```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes(".\openote-release.jks"))
```

Die komplette Ausgabe ohne Änderungen kopieren. Das ist der Wert für das erste
Secret unten.

## 3. Diese vier Secrets in GitHub anlegen

| GitHub Secret-Name | Einzutragender Wert |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Die vollständige Base64-Ausgabe aus Schritt 2 |
| `ANDROID_KEYSTORE_PASSWORD` | Das beim Erzeugen gewählte Keystore-Passwort |
| `ANDROID_KEY_ALIAS` | `openote` |
| `ANDROID_KEY_PASSWORD` | Das beim Erzeugen gewählte Key-Passwort; bei gleicher Wahl also das Keystore-Passwort |

## 4. Danach testen

1. Änderungen pushen und warten, bis **Continuous integration** grün ist.
2. Einen neuen, noch unbenutzten Tag erstellen, z. B. `v0.8.33`.
3. Tag pushen: `git push origin v0.8.33`.
4. In GitHub Actions abwarten, bis **Release packages** fertig ist.
5. Den erzeugten Release-Entwurf öffnen, EXE und APK prüfen und veröffentlichen.

Wichtig: Diesen Keystore nie ersetzen oder verlieren. Android akzeptiert spätere
Updates nur, wenn sie mit genau diesem Schlüssel signiert sind.
