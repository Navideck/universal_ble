#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif
import CoreBluetooth
import Foundation

enum UniversalBlePeripheralError: Error {
  case notFound(String)
  case failed(String)
}

extension PeripheralService {
  func toCBService() -> CBMutableService {
    let service = CBMutableService(type: CBUUID(string: uuid), primary: primary)
    let chars = characteristics.compactMap { $0.toCBCharacteristic() }
    if !chars.isEmpty {
      service.characteristics = chars
    }
    return service
  }
}

extension PeripheralDescriptor {
  func toCBMutableDescriptor() -> CBMutableDescriptor {
    return CBMutableDescriptor(type: CBUUID(string: uuid), value: value?.toData())
  }
}

extension PeripheralCharacteristic {
  func toCBCharacteristic() -> CBMutableCharacteristic {
    let properties = self.properties.compactMap { $0.toCBCharacteristicProperties() }
    let permissions = self.permissions.compactMap { $0.toCBAttributePermissions() }
    var combinedProperties = properties.reduce(CBCharacteristicProperties()) { $0.union($1) }
    if requireEncryptedNotifications == true && combinedProperties.contains(.notify) {
      combinedProperties.remove(.notify)
      combinedProperties.insert(.notifyEncryptionRequired)
    }
    let dynamicProperties: CBCharacteristicProperties = [
      .write, .writeWithoutResponse, .notify, .indicate,
      .notifyEncryptionRequired, .indicateEncryptionRequired,
    ]
    let isDynamic = !combinedProperties.intersection(dynamicProperties).isEmpty
    let combinedPermissions = permissions.reduce(CBAttributePermissions()) { $0.union($1) }
    let characteristic = CBMutableCharacteristic(
      type: CBUUID(string: uuid),
      properties: combinedProperties,
      value: isDynamic ? nil : value?.toData(),
      permissions: combinedPermissions
    )
    characteristic.descriptors = descriptors?.compactMap { $0.toCBMutableDescriptor() }
    return characteristic
  }
}

extension CharacteristicProperty {
  func toCBCharacteristicProperties() -> CBCharacteristicProperties? {
    switch self {
    case .broadcast: return .broadcast
    case .read: return .read
    case .writeWithoutResponse: return .writeWithoutResponse
    case .write: return .write
    case .notify: return .notify
    case .indicate: return .indicate
    case .authenticatedSignedWrites: return .authenticatedSignedWrites
    case .extendedProperties: return .extendedProperties
    }
  }
}

extension PeripheralAttributePermission {
  func toCBAttributePermissions() -> CBAttributePermissions? {
    switch self {
    case .readable: return .readable
    case .writeable: return .writeable
    case .readEncryptionRequired: return .readEncryptionRequired
    case .writeEncryptionRequired: return .writeEncryptionRequired
    }
  }
}

extension Int64 {
  func toCBATTErrorCode() -> CBATTError.Code {
    switch self {
    case 0: return .success
    case 1: return .invalidHandle
    case 2: return .readNotPermitted
    case 3: return .writeNotPermitted
    case 4: return .invalidPdu
    case 5: return .insufficientAuthentication
    case 6: return .requestNotSupported
    case 7: return .invalidOffset
    case 8: return .insufficientAuthorization
    case 9: return .prepareQueueFull
    case 10: return .attributeNotFound
    case 11: return .attributeNotLong
    case 12: return .insufficientEncryptionKeySize
    case 13: return .invalidAttributeValueLength
    case 14: return .unlikelyError
    case 15: return .insufficientEncryption
    case 16: return .unsupportedGroupType
    case 17: return .insufficientResources
    // CoreBluetooth does not expose every ATT status (for example 0x13).
    // Unsupported errors must never silently become successful writes.
    default: return .unlikelyError
    }
  }
}

extension Data {
  func toFlutterBytes() -> FlutterStandardTypedData {
    FlutterStandardTypedData(bytes: self)
  }
}
