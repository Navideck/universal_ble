#!/bin/bash

echo "Building pigeon..."
dart run pigeon --input pigeon/universal_ble.dart
echo "Pigeon built successfully"

echo "Formatting generated files..."
dart format lib/src/universal_ble_pigeon/universal_ble.g.dart
echo "Generated files formatted successfully"

echo "Done"