import CoreBluetooth
import XCTest

@testable import universal_ble

// Unit tests of the Swift portion of this plugin. Run from Xcode, or with
// `xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination '<simulator>'`.

class RunnerTests: XCTestCase {

  func testARefusedOperationCarriesItsAttErrorCode() {
    let refused = NSError(
      domain: CBATTErrorDomain,
      code: CBATTError.Code.insufficientEncryption.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "Encryption is insufficient."]
    )

    let error = refused.toFlutterError()

    XCTAssertEqual(error.code, UniversalBleErrorCode.insufficientEncryption.rawValue.description)
    XCTAssertEqual(error.message, "Encryption is insufficient.")
    XCTAssertEqual(error.details as? String, "15")
  }

  func testEveryAttErrorCodeMapsAsOnAndroid() {
    let expected: [(CBATTError.Code, UniversalBleErrorCode)] = [
      (.invalidHandle, .invalidHandle),
      (.readNotPermitted, .readNotPermitted),
      (.writeNotPermitted, .writeNotPermitted),
      (.invalidPdu, .invalidPdu),
      (.insufficientAuthentication, .insufficientAuthentication),
      (.requestNotSupported, .operationNotSupported),
      (.invalidOffset, .invalidOffset),
      (.insufficientAuthorization, .insufficientAuthorization),
      (.prepareQueueFull, .operationInProgress),
      (.attributeNotFound, .serviceNotFound),
      (.attributeNotLong, .invalidAttributeLength),
      (.insufficientEncryptionKeySize, .insufficientKeySize),
      (.invalidAttributeValueLength, .invalidAttributeLength),
      (.unlikelyError, .failed),
      (.insufficientEncryption, .insufficientEncryption),
      (.unsupportedGroupType, .operationNotSupported),
      (.insufficientResources, .failed),
    ]

    for (attCode, code) in expected {
      XCTAssertEqual(attErrorToUniversalBleErrorCode(attCode.rawValue), code, "ATT code \(attCode.rawValue)")
    }
    XCTAssertEqual(attErrorToUniversalBleErrorCode(0x80), .unknownError, "an application-defined ATT code")
  }

  func testACoreBluetoothErrorWithTheSameNumberIsNotReadAsAnAttCode() {
    // CBError 15 is "encryption timed out", not ATT's "insufficient encryption".
    let timedOut = NSError(domain: CBErrorDomain, code: CBError.Code.encryptionTimedOut.rawValue)

    let error = timedOut.toFlutterError()

    XCTAssertEqual(error.code, UniversalBleErrorCode.unknownError.rawValue.description)
    XCTAssertEqual(error.details as? String, "15")
  }

  func testDiscoveryWaitsAsLongAsTheCallerAsks() {
    let config = DiscoverServicesPlatformConfig(apple: AppleDiscoverServicesOptions(timeoutMillis: 30000))

    XCTAssertEqual(UniversalBleAsyncServiceDiscovery.timeoutSeconds(for: config), 30)
  }

  func testDiscoveryKeepsItsDefaultWithoutATimeout() {
    XCTAssertEqual(UniversalBleAsyncServiceDiscovery.timeoutSeconds(for: nil), 10)
    XCTAssertEqual(UniversalBleAsyncServiceDiscovery.timeoutSeconds(for: DiscoverServicesPlatformConfig()), 10)
    XCTAssertEqual(
      UniversalBleAsyncServiceDiscovery.timeoutSeconds(
        for: DiscoverServicesPlatformConfig(apple: AppleDiscoverServicesOptions(timeoutMillis: 0))),
      10,
      "a timeout of zero would fail every discovery at once")
  }
}
