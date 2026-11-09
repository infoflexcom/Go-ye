$ErrorActionPreference = 'Stop'

# Phase 0 carries a README placeholder rather than a generated Windows runner.
# Delete only that exact placeholder before Flutter generates the real runner.
if ((Test-Path 'windows/README.md') -and @((Get-ChildItem -Path 'windows' -File -Recurse)).Count -eq 1) {
  Remove-Item -Path 'windows' -Recurse -Force
}

# Creates the Windows runner without resolving dependencies. CI runs `flutter
# pub get` explicitly in the following step so failures remain attributable.
flutter create --no-pub --platforms=windows --project-name goye --org org.rccg .

# The Firebase C++ SDK distributed by the FlutterFire Windows plugin still
# declares compatibility with pre-3.5 CMake. Current GitHub Windows images use
# CMake 4, which requires the parent project to opt into that compatibility.
# Keep this generated-runner patch idempotent and scoped to the build policy.
$cmakePath = 'windows/CMakeLists.txt'
$cmake = Get-Content -Raw -Path $cmakePath
$cmakeUpdated = $false
if ($cmake -notmatch 'CMAKE_POLICY_VERSION_MINIMUM') {
  $cmake = [regex]::Replace(
    $cmake,
    '(?m)^(cmake_minimum_required\([^\r\n]+\)\r?\n)',
    "`$1set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING ""Firebase SDK CMake policy compatibility"")`r`n",
    1
  )
  if ($cmake -notmatch 'CMAKE_POLICY_VERSION_MINIMUM') {
    throw 'Unable to set the CMake compatibility policy for the generated Windows runner.'
  }
  $cmakeUpdated = $true
}

# flutter_local_notifications still includes MSVC's experimental coroutine
# headers. Visual Studio 2026 makes their deprecation a compile error; scope
# the vendor-provided compatibility opt-out to this generated desktop runner.
if ($cmake -notmatch '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS') {
  $cmake = [regex]::Replace(
    $cmake,
    '(?m)^(project\([^\r\n]+\)\r?\n)',
    "`$1add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`r`n",
    1
  )
  if ($cmake -notmatch '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS') {
    throw 'Unable to configure Windows notification plugin compiler compatibility.'
  }
  $cmakeUpdated = $true
}

if ($cmakeUpdated) {
  [System.IO.File]::WriteAllText((Resolve-Path $cmakePath), $cmake)
}

New-Item -ItemType Directory -Force -Path 'windows/runner/resources' | Out-Null
Copy-Item -Force 'assets/branding/goye.ico' 'windows/runner/resources/app_icon.ico'
