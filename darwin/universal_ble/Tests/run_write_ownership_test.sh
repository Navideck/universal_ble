#!/bin/bash
# The Apple write-ownership bookkeeping, tested on its own with Xcode's swiftc.
# Unlike run_discovery_progress_test.sh this helper needs no CoreBluetooth, but
# it compiles the same way: optimised, with counted checks that cannot be elided.
# Neither helper is part of the plugin's build (the podspec and Package.swift
# take Sources/ only).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -O -o "$test_dir/write_ownership_test" \
  "$here/../Sources/universal_ble/UniversalBleWriteOwnership.swift" \
  "$here/WriteOwnership/main.swift"
"$test_dir/write_ownership_test"
