#!/bin/bash
# The darwin discovery's bookkeeping, tested
# on its own with Xcode's swiftc. Not part of the plugin's build (the
# podspec and Package.swift take Sources/ only).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(mktemp -d)/discovery_progress_test"
xcrun swiftc -O -o "$bin" \
  "$here/../Sources/universal_ble/UniversalBleDiscoveryProgress.swift" \
  "$here/DiscoveryProgress/main.swift"
"$bin"
