// Unit tests for the Windows ATT error mapping used when a peripheral refuses a
// read, write or subscription. The expected codes match Android's
// gattStatusToUniversalBleErrorCode and Apple's
// attErrorToUniversalBleErrorCode, so the same refusal reports the same
// UniversalBleErrorCode on every platform.

#include "att_error_mapper.h"

#include <iostream>

using universal_ble::AttErrorToUniversalBleErrorCodeValue;

namespace {
bool Check(bool condition, const char *expression, int line) {
  if (condition) {
    return true;
  }
  std::cerr << "CHECK failed at line " << line << ": " << expression
            << std::endl;
  return false;
}
}  // namespace

#define CHECK(expression)                              \
  do {                                                 \
    if (!Check((expression), #expression, __LINE__)) { \
      return 1;                                        \
    }                                                  \
  } while (false)

int main() {
  // UniversalBleErrorCode values (windows/src/generated/universal_ble.g.h).
  constexpr int kUnknownError = 0;
  constexpr int kFailed = 1;
  constexpr int kServiceNotFound = 19;
  constexpr int kInvalidOffset = 23;
  constexpr int kInvalidAttributeLength = 24;
  constexpr int kInvalidPdu = 25;
  constexpr int kInvalidHandle = 26;
  constexpr int kReadNotPermitted = 28;
  constexpr int kWriteNotPermitted = 30;
  constexpr int kOperationNotSupported = 33;
  constexpr int kOperationInProgress = 36;
  constexpr int kInsufficientAuthentication = 50;
  constexpr int kInsufficientAuthorization = 51;
  constexpr int kInsufficientEncryption = 52;
  constexpr int kInsufficientKeySize = 53;

  CHECK(AttErrorToUniversalBleErrorCodeValue(0x01) == kInvalidHandle);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x02) == kReadNotPermitted);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x03) == kWriteNotPermitted);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x04) == kInvalidPdu);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x05) ==
        kInsufficientAuthentication);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x06) == kOperationNotSupported);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x07) == kInvalidOffset);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x08) ==
        kInsufficientAuthorization);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x09) == kOperationInProgress);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0A) == kServiceNotFound);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0B) == kInvalidAttributeLength);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0C) == kInsufficientKeySize);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0D) == kInvalidAttributeLength);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0E) == kFailed);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x0F) == kInsufficientEncryption);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x10) == kOperationNotSupported);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x11) == kFailed);

  // An application-defined ATT code (0x80-0xFF) is not a known protocol error.
  CHECK(AttErrorToUniversalBleErrorCodeValue(0x80) == kUnknownError);
  CHECK(AttErrorToUniversalBleErrorCodeValue(0xFF) == kUnknownError);

  return 0;
}
