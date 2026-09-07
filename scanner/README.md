# Openote Scanner

The Android companion scans paper directly into a selected Openote page. It
does not open, download or expose notebooks.

## Use

1. Open the destination page in Openote on the computer.
2. Choose **Scan from phone** in the top bar and keep the pairing dialog open.
3. Open Openote Scanner on Android and scan the displayed QR code.
4. Scan up to 20 sheets. Each sheet is cropped and enhanced by Android's
   document scanner, then appended to the selected page.

Both devices must be on the same Wi-Fi network. The Windows firewall may ask
whether Openote can receive connections; allow private networks. Closing the
pairing dialog immediately stops the receiver and invalidates its random key.

## GitHub build

The `Android Scanner APK` workflow builds `openote-scanner.apk`. Open its run,
download the `openote-scanner-apk` artifact, unzip it and install the APK on the
phone. Android may ask for permission to install apps from the browser or file
manager used to open it.

