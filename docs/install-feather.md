# Install Velora with Feather

[Feather](https://github.com/khcrysalis/Feather) is an on-device IPA signer and
installer for iOS. It uses an Apple Developer certificate and provisioning
profile to re-sign an IPA for your device.

Velora requires **iOS 26.0 or later** and is iPhone-only. Feather is a
third-party project and is not affiliated with Velora.

## Before you start

You need:

- An iPhone running iOS 26.0 or later.
- The latest Velora IPA from the
  [releases page](https://github.com/CRZX1337/velora-ios/releases).
- Feather installed and trusted on the iPhone.
- A valid Apple Developer signing certificate in `.p12` format and its password.
- A `.mobileprovision` provisioning profile that is valid for that certificate
  and can sign the bundle identifier you will use. For a development
  certificate, the profile must also include your iPhone's UDID.
- The IPA saved in the Files app.

Feather itself must be installed with a signing identity before it can sign
other apps. If Feather is not installed yet, follow Feather's official
installation guidance and use a certificate you own. Do not use a certificate,
profile or pre-signed app from an untrusted source.

## 1. Prepare Feather

1. Open Feather.
2. Open **Settings**.
3. Find the **Signing** section.
4. Import the `.p12` certificate and the matching `.mobileprovision` profile.
5. Enter the certificate password when prompted.

Feather's certificate handling and profile requirements are documented in the
[official Feather wiki](https://github.com/khcrysalis/Feather/wiki).

## 2. Import Velora

1. Download the Velora IPA on the iPhone and save it in Files.
2. In Feather, open **Library**.
3. Tap the add button and choose the Velora IPA from Files.
4. Wait until the app appears in the library.

## 3. Sign the IPA

1. Tap Velora in the library.
2. Choose **Sign**.
3. Keep the default signing options unless you specifically need a change.
   Changing the bundle identifier can create a separate app and is not required
   for a normal installation.
4. Start signing and wait for Feather to report success.

Do not enable tweak injection or unrelated modifications for a normal Velora
installation.

## 4. Install

1. After signing succeeds, choose **Install**.
2. Confirm the iOS installation prompt.
3. Wait for the Velora icon to appear on the Home Screen.
4. If iOS reports an untrusted developer, open
   **Settings → General → VPN & Device Management**, select the developer
   certificate and trust it.

The exact labels can differ slightly between Feather versions. If a label has
moved, use Feather's current interface and official documentation.

## 5. First launch

1. Open Velora.
2. Allow location access **While Using the App**.
3. Tap **Start Trip**.
4. Keep the app in the foreground while recording. Velora pauses a running trip
   when the app leaves the foreground.

See the [main README](../README.md) for the product guide and privacy details.

## Troubleshooting

- **Signing fails:** Check that the certificate is valid, the password is
  correct, the profile is valid for this signing method and it can sign the
  selected bundle identifier. A development profile must include this iPhone.
- **Install fails:** Confirm that the certificate has not expired and that the
  profile is still valid. Re-sign the IPA after changing either file.
- **The app opens and immediately closes:** Check the developer trust settings
  and confirm that the certificate is still valid.
- **Velora will not launch:** Velora requires iOS 26.0 or later. Check the iOS
  version before retrying.
- **Feather cannot open the IPA:** Use the current official Feather release and
  confirm that the download completed without an HTML error page.

## Official Feather documentation

- [Feather repository](https://github.com/khcrysalis/Feather)
- [Feather releases](https://github.com/khcrysalis/Feather/releases)
- [Feather wiki](https://github.com/khcrysalis/Feather/wiki)
- [Using an Apple Developer Account](https://github.com/khcrysalis/Feather/wiki/Using-an-Apple-Developer-Account)
- [Feather troubleshooting](https://github.com/khcrysalis/Feather/wiki/Troubleshooting)
