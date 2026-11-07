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
