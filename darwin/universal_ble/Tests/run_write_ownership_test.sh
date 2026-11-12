#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -o "$test_dir/write_ownership_test" \
  "$here/../Sources/universal_ble/UniversalBleWriteOwnership.swift" \
  "$here/WriteOwnership/main.swift"
"$test_dir/write_ownership_test"
