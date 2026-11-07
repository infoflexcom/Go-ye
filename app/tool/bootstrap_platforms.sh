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

# Replace every generated iOS AppIcon rendition with the approved logo. The
# runner's launch storyboard then hands off to the in-app branded splash.
if [ -d ios/Runner/Assets.xcassets/AppIcon.appiconset ]; then
  find ios/Runner/Assets.xcassets/AppIcon.appiconset -name '*.png' -type f -exec sh -c '
    size=$(identify -format "%wx%h" "$1")
    convert assets/branding/logo.jpg -background white -gravity center -extent "$size" "$1"
  ' sh {} \;
fi

# Replace the generated Android launcher densities with images rendered from
# logo.jpg. The in-app restoring screen is the branded cross-platform splash.
for spec in 'mipmap-mdpi 48' 'mipmap-hdpi 72' 'mipmap-xhdpi 96' 'mipmap-xxhdpi 144' 'mipmap-xxxhdpi 192'; do
  set -- $spec
  mkdir -p "android/app/src/main/res/$1"
  convert assets/branding/logo.jpg -background white -gravity center -extent "$2x$2" \
    "android/app/src/main/res/$1/ic_launcher.png"
done
