#!/bin/bash
# The central state restoration identifier's ownership, tested on its own with
# Xcode's swiftc: no Flutter, no CoreBluetooth, no device. Not part of the
# plugin's build (the podspec and Package.swift take Sources/ only).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
bin="$test_dir/central_restoration_owner_test"
xcrun swiftc -O -o "$bin" \
  "$here/../Sources/universal_ble/UniversalBleCentralRestorationOwner.swift" \
  "$here/CentralRestorationOwner/main.swift"
"$bin"
