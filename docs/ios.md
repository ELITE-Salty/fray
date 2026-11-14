# iOS build and distribution

## Current status

The app has a Flutter iOS target (minimum iOS 15), with English/Slovenian/Croatian declarations and Keychain entitlements for secure session/workspace storage. The current workstation runs Linux and has no Xcode. No Apple signing team, provisioning profile or iPhone is available. **No installable IPA has been built or tested.** The native configuration still needs its first Xcode build and device validation.

`dist/ios/fray-ios-source-0.2.0+2.zip` is a source handoff for a Mac. It is **not an installer** and contains no IPA. It includes Flutter source, assets, dependency locks, the iOS target, this guide and the build script. It excludes build caches, the backend, environment secrets and Apple signing material. `dist/` is ignored by Git.

Create a fresh source handoff from the Git checkout with:

```sh
python3 scripts/build-ios.py --source-only
```

The command refuses to overwrite an existing same-version archive. Use `--output /another/directory` to keep a separate snapshot. The ZIP is accompanied by a SHA-256 checksum.

## What is needed to make an installable build

Flutter requires **macOS with Xcode** to compile the native iOS app. A borrowed Mac or a hosted macOS builder can supply that environment; a Linux Docker image cannot replace the Apple SDK/toolchain. Hosted builds still need Apple signing for device installation.

For testing on a particular connected iPhone, Xcode supports signing with a free Apple Account/Personal Team, subject to Apple's limits. That needs access to a Mac and the device; it is not a broadly shareable installer.

For distributing to testers without registering their phones first, use **TestFlight** through an Apple Developer Program account and App Store Connect. An App Store-signed IPA is uploaded to Apple, and testers install through TestFlight. Apple may require beta review. You do not need to own an iPhone to prepare and upload that build, but someone should validate the app on a real device.

For a directly distributed **ad hoc IPA**, the target iPhones must be registered with Apple and included in the provisioning profile before export. An IPA is not a universal installer that anyone can tap to install like an Android APK. An unsigned archive or simulator application is not a signed phone installer.

Do not send Apple passwords, certificate private keys or App Store Connect API keys in chat or commit them to Git. Configure them in Xcode/the macOS Keychain or your selected CI secret store.

## First Mac setup

1. Install Xcode and its iOS SDK; open it once to finish setup and accept the license. Select that Xcode installation with `xcode-select` if needed.
2. Install Flutter **3.47.9 / Dart 3.13.7** (the project's pinned baseline), Python **3.11+**, and any plugin prerequisites reported by `flutter doctor -v`. This target uses Flutter's Swift Package Manager integration; Flutter may require CocoaPods for plugin fallback.
3. Extract the source ZIP, or clone the GitHub repo. From `apps/fray`, run `flutter pub get --enforce-lockfile`, then open `ios/Runner.xcworkspace`.
4. Select **Runner → Signing & Capabilities**, choose your Apple team and a bundle identifier registered to it. The current `dev.fray.fray` is a placeholder, not a claim that it is registered in your Apple account. Keep the same identifier across updates after distribution.
5. Confirm Keychain entitlements apply to Debug, Profile and Release. The app does not share credentials with other apps or use an App Group. Add/review capabilities through Xcode if signing requests it.
6. Build/run on a simulator, then validate on an iPhone. Use only disposable simulators for integration tests; development tools can reinstall apps after installation failures.

Before wider distribution, review the placeholder launcher icons, App Store privacy/export-compliance declarations, plugin privacy manifests, signing settings and Apple review requirements. These have not been certified as store-ready by this Linux-side preparation.

## Build into a separate distribution folder

Once Xcode signing is configured, from the repository/extracted archive root:

```sh
# App Store Connect / TestFlight export:
python3 scripts/build-ios.py --method app-store

# Direct installation on devices registered in your ad hoc profile:
python3 scripts/build-ios.py --method ad-hoc

# Or use the export settings saved by Xcode's distribution wizard:
python3 scripts/build-ios.py --export-options /private/ExportOptions.plist
```

The script runs `flutter build ipa --release`, targeting `https://frayapi.klanija.com`. Override with `--api-url https://your-api.example.org`; plain HTTP and URLs with credentials are rejected. `--build-number 3` can select a new Apple build number without editing the shared Android version. Increase build numbers for subsequent App Store Connect uploads.

It checks for a **freshly exported** IPA, verifies its code signature using Apple's `codesign`, checks for an embedded provisioning profile, and copies it to:

```text
dist/ios/fray-ios-<unique-id>/
  Fray.ipa
  SHA256SUMS
  build.json
```

This folder is outside `apps/fray/build`, so `flutter clean` will not delete the distribution copy. The original build/archive stays available for Xcode diagnostics. Existing distributions are preserved. If Flutter builds an archive but fails to export/sign an IPA, the script reports failure and does not copy an old artifact. Signature validation does not establish that an arbitrary phone is included in the profile or that Apple will accept the upload.

The successful macOS/signing path has not run here. Linux-side checks cover Python syntax, argument/help handling, source packaging, archive contents/checksum, and refusal to pretend an IPA was built on Linux.

## Before inviting testers

Deploy the matching Fray backend first. On iPhone/iPad, check login and MFA, email verification/reset, Keychain persistence across restart, offline entry sync, timezone/12–24-hour pickers, Light/Dark/System, all three languages, and the native CSV/PDF share sheet (including iPad popover placement). Test account deletion and confirm recovery codes are saved outside the app.

For immediate iPhone access, open `https://frayapi.klanija.com` in Safari. The existing web app can be added to the Home Screen; that is web access, not a native IPA, and does not validate native plugins.

## References

- [Flutter: build and release an iOS app](https://docs.flutter.dev/deployment/ios)
- [Apple: developer account and membership](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Apple: distribution methods](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html)
- [Apple: registering test devices](https://developer.apple.com/help/account/devices/devices-overview/)
