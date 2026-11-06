# Go-Ye Flutter client

One Flutter codebase targets Android 8+, iOS 15+ and Windows 10/11. Riverpod is established as the state-management foundation. Drift/SQLCipher, secure storage, localisation and the domain modules are intentionally deferred until the secure data phase; no convert data can be captured by this Phase 0 shell.

## First local run

Install a current stable Flutter SDK with Android and/or Windows desktop tooling, then run:

```bash
cd app
./tool/bootstrap_platforms.sh
flutter pub get
flutter test
flutter analyze
flutter run                 # Select an Android emulator or Windows device.
```

The bootstrap script is intentionally committed because this Linux workspace does not include Flutter, Android SDK, Java or a Windows toolchain. It produces the standard platform runner projects from the pinned/available stable Flutter SDK while preserving `lib/` and `test/`.

## Branding boundary

The approved RCCG logo source is at `../assets/logo.jpg`; INFOFLEX's source is at `../assets/logo-source.png`. Neither is wired into an application icon in this phase. This avoids making an unconfirmed trademark/brand usage decision before the requested written confirmation. Once approved, the RCCG logo will be processed into Android, iOS and Windows icon/splash sizes; INFOFLEX remains restricted to About/Built-by, installer and admin footer contexts.
