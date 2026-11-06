# Go-Ye Flutter client

One Flutter codebase targets Android 8+, iOS 15+ and Windows 10/11. Riverpod is established as the state-management foundation. OTP session storage uses the platform keystore/keychain through `flutter_secure_storage`; the app never stores tokens in files or preferences. The online-first client is configured with an `API_BASE_URL` launch value so phone and desktop connect to the same NestJS/PostgreSQL server. Offline sync remains a later phase.

## First local run

Install a current stable Flutter SDK with Android and/or Windows desktop tooling, then run:

```bash
cd app
./tool/bootstrap_platforms.sh
flutter pub get
flutter test
flutter analyze
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1/ # Android emulator
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:3000/api/v1/
```

The bootstrap script is intentionally committed because this Linux workspace does not include Flutter, Android SDK, Java or a Windows toolchain. It produces the standard platform runner projects from the pinned/available stable Flutter SDK while preserving `lib/` and `test/`.

## Branding

`assets/branding/logo.jpg` is the approved RCCG source used by the app logo, restoring splash, Android launcher images and the Windows `goye.ico`. Run `./tool/bootstrap_platforms.sh` after installing Flutter to regenerate runner projects and restore native icon files. `tool/bootstrap_windows.ps1` performs the equivalent Windows runner/icon setup for CI.

`assets/branding/infoflex-logo.png` is used only on the in-app **About / Built by** surface. It is not used as an app icon, splash image or general client branding.

## Same server on Android and Windows

Both launches must use the same API URL and authorised credentials. For an Android emulator against a backend on the development host, use `http://10.0.2.2:3000/api/v1/`; for Windows running on that host, use `http://localhost:3000/api/v1/`. For a physical phone and a separate Windows machine, use the same TLS LAN/VPN hostname, for example `https://goye-pilot.example.org/api/v1/`. Do not use `localhost` on a physical phone: it refers to the phone itself.
