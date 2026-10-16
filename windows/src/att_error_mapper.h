#pragma once

#include <cstdint>

namespace universal_ble {

/// Maps a Bluetooth ATT error code (a `GattProtocolError` value, i.e. the
/// `ProtocolError` byte of a GATT read/write result) to the raw value of the
/// matching `UniversalBleErrorCode`.
///
/// Mirrors Android's `gattStatusToUniversalBleErrorCode` and Apple's
/// `attErrorToUniversalBleErrorCode`, so a peripheral refusing a read, write or
/// subscription reports the same code on every platform. The result is the
/// `UniversalBleErrorCode` integer rather than the enum itself, which keeps
/// this free of flutter/winrt types so it can be unit tested without a Flutter
/// engine (see windows/test/att_error_mapper_test.cpp).
int AttErrorToUniversalBleErrorCodeValue(uint8_t att_error);

}  // namespace universal_ble
