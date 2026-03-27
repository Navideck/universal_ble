#!/bin/bash

echo "Building pigeon..."
dart run pigeon --input pigeon/universal_ble.dart
dart run pigeon --input pigeon/universal_ble_peripheral.dart
echo "Pigeon built successfully"

echo "Formatting generated files..."
dart format lib/src/universal_ble_pigeon/universal_ble.g.dart
dart format lib/src/universal_ble_peripheral/generated/universal_ble_peripheral.g.dart
echo "Generated files formatted successfully"

echo "Done"