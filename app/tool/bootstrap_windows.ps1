$ErrorActionPreference = 'Stop'

# Phase 0 carries a README placeholder rather than a generated Windows runner.
# Delete only that exact placeholder before Flutter generates the real runner.
if ((Test-Path 'windows/README.md') -and @((Get-ChildItem -Path 'windows' -File -Recurse)).Count -eq 1) {
  Remove-Item -Path 'windows' -Recurse -Force
}

# Creates the Windows runner without resolving dependencies. CI runs `flutter
# pub get` explicitly in the following step so failures remain attributable.
flutter create --no-pub --platforms=windows --project-name goye --org org.rccg .
New-Item -ItemType Directory -Force -Path 'windows/runner/resources' | Out-Null
Copy-Item -Force 'assets/branding/goye.ico' 'windows/runner/resources/app_icon.ico'
