#include "att_error_mapper.h"

namespace universal_ble {

// ATT error codes (Bluetooth Core Spec, Vol 3, Part F, 3.4.1.1).
//
// The right-hand values are the `UniversalBleErrorCode` integer values from
// windows/src/generated/universal_ble.g.h. They are pinned there (the enum uses
// explicit `= N` values) and shared with the Dart and Android layers, so they
// do not shift. Kept in lockstep with Android's
// `gattStatusToUniversalBleErrorCode` and Apple's
// `attErrorToUniversalBleErrorCode`:
//
//   1 kFailed                  19 kServiceNotFound
//   23 kInvalidOffset          24 kInvalidAttributeLength
//   25 kInvalidPdu             26 kInvalidHandle
//   28 kReadNotPermitted       30 kWriteNotPermitted
//   33 kOperationNotSupported  36 kOperationInProgress
//   50 kInsufficientAuthentication  51 kInsufficientAuthorization
//   52 kInsufficientEncryption      53 kInsufficientKeySize
int AttErrorToUniversalBleErrorCodeValue(uint8_t att_error) {
  switch (att_error) {
    case 0x01:
      return 26;  // kInvalidHandle
    case 0x02:
      return 28;  // kReadNotPermitted
    case 0x03:
      return 30;  // kWriteNotPermitted
    case 0x04:
      return 25;  // kInvalidPdu
    case 0x05:
      return 50;  // kInsufficientAuthentication
    case 0x06:
      return 33;  // kOperationNotSupported (request not supported)
    case 0x07:
      return 23;  // kInvalidOffset
    case 0x08:
      return 51;  // kInsufficientAuthorization
    case 0x09:
      return 36;  // kOperationInProgress (prepare queue full)
    case 0x0A:
      return 19;  // kServiceNotFound (attribute not found)
    case 0x0B:
      return 24;  // kInvalidAttributeLength (attribute not long)
    case 0x0C:
      return 53;  // kInsufficientKeySize
    case 0x0D:
      return 24;  // kInvalidAttributeLength
    case 0x0E:
      return 1;  // kFailed (unlikely error)
    case 0x0F:
      return 52;  // kInsufficientEncryption
    case 0x10:
      return 33;  // kOperationNotSupported (unsupported group type)
    case 0x11:
      return 1;  // kFailed (insufficient resources)
    default:
      return 0;  // kUnknownError (incl. application-defined 0x80-0xFF)
  }
}

}  // namespace universal_ble
