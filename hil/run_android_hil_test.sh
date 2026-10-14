#!/bin/bash
# Run HIL integration tests on Android with auto-granted Bluetooth permissions.
#
# Usage:
#   ./run_android_hil_test.sh integration_test/baseline_hil_test.dart [device-id]
#   ./run_android_hil_test.sh integration_test/fault_injection_hil_test.dart [device-id]
#
# Without a device ID, adb uses the connected Android device.

set -euo pipefail

TEST_FILE="${1:?Missing test file path}"
DEVICE_ID="${2:-}"
PACKAGE="com.example.universal_ble_hil"
PERMISSIONS=(
  "android.permission.BLUETOOTH_SCAN"
  "android.permission.BLUETOOTH_CONNECT"
  "android.permission.ACCESS_FINE_LOCATION"
)

cd "$(dirname "$0")"

DEVICE_ARG=()
ADB_TARGET=()
if [ -n "$DEVICE_ID" ]; then
  DEVICE_ARG=(-d "$DEVICE_ID")
  ADB_TARGET=(-s "$DEVICE_ID")
fi

echo "==> Starting: flutter test $TEST_FILE ${DEVICE_ARG[*]}"
echo "==> Permissions will be granted after installation..."

# Run Flutter in the background so permissions can be granted between APK
# installation and test execution.
flutter test "$TEST_FILE" "${DEVICE_ARG[@]}" &
FLUTTER_PID=$!

GRANTED=false
for _ in $(seq 1 60); do
  sleep 1
  if adb "${ADB_TARGET[@]}" shell pm list packages 2>/dev/null | grep -q "package:$PACKAGE"; then
    for permission in "${PERMISSIONS[@]}"; do
      adb "${ADB_TARGET[@]}" shell pm grant "$PACKAGE" "$permission" 2>/dev/null || true
    done
    echo "==> Permission grants attempted"
    GRANTED=true
    break
  fi
done

if [ "$GRANTED" = false ]; then
  echo "==> WARNING: Timed out waiting for package installation. Permissions may need to be granted manually."
fi

# Preserve Flutter's exit code without set -e terminating the script first.
if wait "$FLUTTER_PID"; then
  EXIT_CODE=0
else
  EXIT_CODE=$?
fi

echo "==> Done (exit $EXIT_CODE)"
exit "$EXIT_CODE"
