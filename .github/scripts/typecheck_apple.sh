#!/usr/bin/env bash
#
# Typechecks the shared Apple plugin sources against the Flutter engine
# frameworks, once for macOS and once for iOS. The sources branch on
# `#if os(...)` and import FlutterMacOS or Flutter, so one platform's module
# only proves that platform's branch.
#
# Run by the `apple` job in .github/workflows/pull_request.yml. Pass
# --download-only to fetch the frameworks without typechecking.
#
# The engine layout differs between Flutter versions: the macOS framework can
# be a bare FlutterMacOS.framework beside the engine artifacts, or a slice
# inside FlutterMacOS.xcframework, and its directory is named after the host
# arch (darwin-x64, darwin-arm64). A cached SDK can also contain the directory
# without the framework, in which case `flutter precache` treats it as done and
# skips the download. So: look for the framework, force the download when it is
# missing, then use the path that was found.

set -euo pipefail

flutter_root="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
engine="$flutter_root/bin/cache/artifacts/engine"

# Echoes the directory that holds the macOS FlutterMacOS.framework, else fails.
macos_framework_dir() {
  local dir found
  for dir in "$engine"/darwin-x64 "$engine"/darwin-arm64; do
    [ -d "$dir" ] || continue
    found="$(find "$dir" -maxdepth 3 -type d -name FlutterMacOS.framework -print -quit)"
    if [ -n "$found" ]; then
      dirname "$found"
      return 0
    fi
  done
  return 1
}

# Echoes the directory that holds the iOS Flutter.framework, else fails.
ios_framework_dir() {
  local xcframework="$engine/ios/Flutter.xcframework" found
  [ -d "$xcframework" ] || return 1
  found="$(find "$xcframework" -maxdepth 2 -type d -name ios-arm64 -print -quit)"
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

have_frameworks() {
  macos_framework_dir >/dev/null && ios_framework_dir >/dev/null
}

flutter precache --macos --ios
if ! have_frameworks; then
  flutter precache --force --macos --ios
fi
if ! have_frameworks; then
  echo "Apple engine frameworks are missing under $engine" >&2
  find "$engine" -maxdepth 2 -type d -print | sed -n '1,20p' >&2
  exit 1
fi

if [ "${1:-}" = "--download-only" ]; then
  exit 0
fi

macos_framework_dir="$(macos_framework_dir)"
ios_framework_dir="$(ios_framework_dir)"
sources=(darwin/universal_ble/Sources/universal_ble/*.swift)

xcrun swiftc -typecheck \
  -target "$(uname -m)-apple-macos10.15" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -F "$macos_framework_dir" \
  "${sources[@]}"

xcrun swiftc -typecheck \
  -target arm64-apple-ios13.1 \
  -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -F "$ios_framework_dir" \
  "${sources[@]}"
