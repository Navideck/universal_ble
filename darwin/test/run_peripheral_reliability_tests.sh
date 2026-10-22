#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
flutter_sdk="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
frameworks="$flutter_sdk/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -F "$frameworks" -framework FlutterMacOS -framework CoreBluetooth \
  -Xlinker -rpath -Xlinker "$frameworks" \
  darwin/universal_ble/Sources/universal_ble/*.swift \
  darwin/test/peripheral_reliability_test.swift -o "$test_dir/peripheral-tests"
"$test_dir/peripheral-tests"
