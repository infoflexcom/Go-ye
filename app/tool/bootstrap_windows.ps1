$ErrorActionPreference = 'Stop'

# Creates the Windows runner then restores the supplied RCCG logo as its icon.
# The .ico is generated from assets/logo.jpg and tracked under app/assets.
flutter create --platforms=windows --project-name goye --org org.rccg .
New-Item -ItemType Directory -Force -Path 'windows/runner/resources' | Out-Null
Copy-Item -Force 'assets/branding/goye.ico' 'windows/runner/resources/app_icon.ico'
