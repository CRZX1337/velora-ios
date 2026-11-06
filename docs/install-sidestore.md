# Install Velora with SideStore

[SideStore](https://sidestore.io/) is an on-device sideloading app that uses your
Apple Account to sign and install IPAs. It needs a computer only for the initial
installation and uses LocalDevVPN for later installs and refreshes.

Velora requires **iOS 26.0 or later** and is iPhone-only. SideStore is a
third-party project and is not affiliated with Velora.

## Before you start

You need:

- An iPhone with a passcode, running iOS 26.0 or later.
- A Windows, macOS or Linux computer for the initial SideStore installation.
- A USB cable.
- An Apple Account.
- A Wi-Fi connection. Mobile data is not sufficient for setup.
- The latest Velora IPA from the
  [releases page](https://github.com/CRZX1337/velora-ios/releases), saved in
  Files.
- [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044) installed
  from the App Store.
- [iloader](https://iloader.app/) installed on the computer.

A free Apple Account has limits: SideStore can install three apps at a time,
including SideStore itself, and only ten different app IDs may be installed in a
week. Apps signed with a free account normally need refreshing every seven days.
A paid Apple Developer account removes the three-app limit and gives a longer
signing period.

## 1. Prepare the VPN

1. Install LocalDevVPN on the iPhone.
2. Open it and tap **Connect**.
3. If iOS asks to allow VPN configurations, allow it and enter the passcode.

SideStore uses this local VPN to install and refresh apps. Keep it connected
whenever you install or refresh something in SideStore.

## 2. Install SideStore

These steps follow the official
[SideStore installation guide](https://docs.sidestore.io/docs/installation/install).

1. Connect the iPhone to the computer with the USB cable.
2. If the iPhone asks whether to trust the computer, trust it and enter the
   passcode.
3. Open iloader on the computer.
4. Sign in with the Apple Account you want to use. The account name is
   case-sensitive.
5. Select the iPhone.
6. Choose **Install SideStore (Stable)**.
7. Wait until iloader finishes installing SideStore on the device.

## 3. Trust SideStore on the iPhone

1. Open **Settings**.
2. Open **General → VPN & Device Management**.
3. Under the developer app section, select the entry named after your Apple
   Account.
4. Choose **Trust** and confirm with the passcode.
5. Open **Settings → Privacy & Security**.
6. Turn on **Developer Mode** and restart the iPhone when prompted.
7. After the restart, open LocalDevVPN again and connect it.
8. Open SideStore.
9. Sign in with the same Apple Account.
10. Open **My Apps**.
11. Tap the **7 DAYS** counter next to SideStore to refresh SideStore itself.
12. If SideStore asks to revoke or create a signing certificate, confirm.

Refreshing SideStore immediately after setup matters: it completes SideStore's
signing setup and ensures later apps use the correct app group.

## 4. Install Velora

1. Download the Velora IPA and save it in Files.
2. Make sure LocalDevVPN is connected.
3. In Files, open the IPA and choose SideStore from the share sheet. If your
   SideStore version exposes an import or install control in **My Apps**, you can
   use that instead.
4. If SideStore asks, sign in with the same Apple Account.
5. Wait for signing and installation to finish. The Velora icon should appear on
   the Home Screen.
6. If iOS asks for trust, repeat the developer-app trust step above.

## 5. First launch

1. Open Velora.
2. Allow location access **While Using the App**.
3. Tap **Start Trip**.
4. Keep the app in the foreground while recording. Velora pauses a running trip
   when the app leaves the foreground.

See the [main README](../README.md) for the product guide and privacy details.

## Keeping Velora signed

With a free Apple Account, open LocalDevVPN, open SideStore, go to **My Apps** and
refresh Velora before its seven-day signing period expires. SideStore may refresh
apps in the background, but opening it and refreshing manually is the reliable
option.

The pairing file used by SideStore can expire after an iOS update or reset. Follow
SideStore's official
[pairing file guide](https://docs.sidestore.io/docs/advanced/pairing-file) if
SideStore can no longer connect to the device.

## Troubleshooting

- **Installation does not start:** Confirm that LocalDevVPN is connected, the
  iPhone is on Wi-Fi and SideStore is up to date.
- **SideStore cannot sign in:** Check the Apple Account credentials and the
  Anisette server setting in SideStore's settings. The official FAQ lists known
  sign-in issues.
- **The app stops opening after a few days:** Refresh Velora in SideStore while
  LocalDevVPN is connected before the signing period expires.
- **Trust prompt is missing:** Make sure Developer Mode is enabled and check
  **Settings → General → VPN & Device Management**.
- **The IPA will not install:** Confirm that it is the Velora IPA, that the
  download completed and that the device runs iOS 26.0 or later.
- **Velora cannot use location:** Open **Settings → Privacy & Security → Location
  Services → Velora** and allow access while using the app.

## Official SideStore documentation

- [SideStore prerequisites](https://docs.sidestore.io/docs/installation/prerequisites)
- [Install SideStore](https://docs.sidestore.io/docs/installation/install)
- [SideStore FAQ](https://docs.sidestore.io/docs/faq)
- [Pairing file guide](https://docs.sidestore.io/docs/advanced/pairing-file)
- [SideStore troubleshooting](https://docs.sidestore.io/docs/troubleshooting)
- [SideStore website](https://sidestore.io/)

Support for SideStore, iloader and LocalDevVPN belongs to those projects.
