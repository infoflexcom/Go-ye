#!/usr/bin/env sh
set -eu

# Phase 0 carried lightweight platform README placeholders instead of generated
# runners. Remove only those exact placeholders; never replace a real runner.
remove_placeholder_runner() {
  platform="$1"
  if [ -f "$platform/README.md" ] && [ "$(find "$platform" -type f | wc -l | tr -d ' ')" = "1" ]; then
    rm -rf "$platform"
  fi
}

remove_placeholder_runner android
remove_placeholder_runner ios
remove_placeholder_runner windows

# Generates or refreshes Android, iOS and Windows runners without replacing
# lib/ or test/. Dependency resolution happens in the subsequent `flutter pub
# get` CI step, so runner generation cannot mask a package-resolution failure.
flutter create --no-pub --platforms=android,ios,windows --project-name goye --org org.rccg .

# Android 13+ requires this runtime-granted permission before a local foreground
# or FCM notification can be shown. The client requests it through the local
# notification plugin; the church-owned Firebase config is injected separately.
android_manifest='android/app/src/main/AndroidManifest.xml'
if [ -f "$android_manifest" ] && ! grep -q 'android.permission.POST_NOTIFICATIONS' "$android_manifest"; then
  tmp_manifest="${android_manifest}.tmp"
  awk '
    /<manifest / {
      print
      print "    <uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\" />"
      next
    }
    { print }
  ' "$android_manifest" > "$tmp_manifest"
  mv "$tmp_manifest" "$android_manifest"
fi

# flutter_local_notifications requires Java 8+ API desugaring on Android. Add
# it after each generated runner refresh so a debug build works without any
# church Firebase configuration. Support both current Kotlin DSL templates and
# older Groovy templates used by a locally pinned Flutter SDK.
configure_android_desugaring() {
  gradle_file="$1"
  syntax="$2"
  [ -f "$gradle_file" ] || return 0
  grep -q 'coreLibraryDesugaring' "$gradle_file" && return
  python3 - "$gradle_file" "$syntax" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
syntax = sys.argv[2]
source = path.read_text()
line_ending = '\r\n' if '\r\n' in source else '\n'
compile_options = re.search(r'(?m)^([ \t]*)compileOptions\s*\{\r?\n', source)
if compile_options is None:
    raise SystemExit(f'Unable to find compileOptions in {path}')
indent = compile_options.group(1)
if syntax == 'kts':
    setting = f'{indent}    isCoreLibraryDesugaringEnabled = true{line_ending}'
    dependency = (
        f'{line_ending}dependencies {{{line_ending}'
        f'{indent}coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4"){line_ending}'
        f'}}{line_ending}'
    )
else:
    setting = f'{indent}    coreLibraryDesugaringEnabled true{line_ending}'
    dependency = (
        f'{line_ending}dependencies {{{line_ending}'
        f"{indent}coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'{line_ending}"
        f'}}{line_ending}'
    )
source = source[:compile_options.end()] + setting + source[compile_options.end():]
flutter_block = re.search(r'(?m)^[ \t]*flutter\s*\{', source)
if flutter_block is None:
    source = source.rstrip() + line_ending + dependency
else:
    prefix = source[:flutter_block.start()].rstrip()
    source = prefix + line_ending + dependency + source[flutter_block.start():]
path.write_text(source)
PY
}

configure_android_desugaring 'android/app/build.gradle.kts' kts
configure_android_desugaring 'android/app/build.gradle' groovy

# Flutter's generated Windows runner expects this exact icon file. It is built
# from the approved RCCG logo (not the INFOFLEX logo) and is intentionally
# copied after every flutter create refresh.
mkdir -p windows/runner/resources
cp assets/branding/goye.ico windows/runner/resources/app_icon.ico

# Pre-rendered native renditions are derived from the approved logo.jpg and
# tracked so bootstrap works on Flutter runners without ImageMagick. The runner
# launch storyboard then hands off to the in-app branded splash.
if [ -d ios/Runner/Assets.xcassets/AppIcon.appiconset ]; then
  cp assets/branding/ios_app_icons/*.png ios/Runner/Assets.xcassets/AppIcon.appiconset/
fi

# Replace the generated Android launcher densities with the pre-rendered RCCG
# logo assets. The in-app restoring screen is the branded cross-platform splash.
for spec in 'mipmap-mdpi 48' 'mipmap-hdpi 72' 'mipmap-xhdpi 96' 'mipmap-xxhdpi 144' 'mipmap-xxxhdpi 192'; do
  set -- $spec
  mkdir -p "android/app/src/main/res/$1"
  cp "assets/branding/android_launcher/ic_launcher_$2.png" "android/app/src/main/res/$1/ic_launcher.png"
done
