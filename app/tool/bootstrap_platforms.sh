#!/usr/bin/env sh
set -eu

# Generates or refreshes the Android, iOS and Windows runner projects from the
# installed stable Flutter SDK without replacing lib/ or test/ application code.
flutter create --platforms=android,ios,windows --project-name goye --org org.rccg .
