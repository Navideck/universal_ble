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
}

var peripheralCharacteristicsList = [CBMutableCharacteristic]()
var peripheralServicesList = [CBMutableService]()

func clearPeripheralCaches() {
  peripheralCharacteristicsList.removeAll()
  peripheralServicesList.removeAll()
}

extension PeripheralService {
  func toCBService() -> CBMutableService {
    let service = CBMutableService(type: CBUUID(string: uuid), primary: primary)
    let chars = characteristics.compactMap { $0.toCBCharacteristic() }
    if !chars.isEmpty {
      service.characteristics = chars
    }
    peripheralServicesList.removeAll {
      $0.uuid.uuidString.lowercased() == service.uuid.uuidString.lowercased()
    }
    peripheralServicesList.append(service)
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
    let combinedProperties = properties.reduce(CBCharacteristicProperties()) { $0.union($1) }
    let combinedPermissions = permissions.reduce(CBAttributePermissions()) { $0.union($1) }
    let characteristic = CBMutableCharacteristic(
      type: CBUUID(string: uuid),
      properties: combinedProperties,
      value: value?.toData(),
      permissions: combinedPermissions
    )
    characteristic.descriptors = descriptors?.compactMap { $0.toCBMutableDescriptor() }
    peripheralCharacteristicsList.removeAll {
      $0.uuid.uuidString.lowercased() == characteristic.uuid.uuidString.lowercased()
    }
    peripheralCharacteristicsList.append(characteristic)
    return characteristic
  }
}

extension String {
  func findPeripheralCharacteristic() -> CBMutableCharacteristic? {
    peripheralCharacteristicsList.first { $0.uuid.uuidString == self }
  }

  func findPeripheralService() -> CBMutableService? {
    peripheralServicesList.first { $0.uuid.uuidString == self }
  }
}

extension Int64 {
  func toCBCharacteristicProperties() -> CBCharacteristicProperties? {
    switch self {
    case 0: return .broadcast
    case 1: return .read
    case 2: return .writeWithoutResponse
    case 3: return .write
    case 4: return .notify
    case 5: return .indicate
    case 6: return .authenticatedSignedWrites
    case 7: return .extendedProperties
    case 8: return .notifyEncryptionRequired
    case 9: return .indicateEncryptionRequired
    default: return nil
    }
  }

  func toCBAttributePermissions() -> CBAttributePermissions? {
    switch self {
    case 0: return .readable
    case 1: return .writeable
    case 2: return .readEncryptionRequired
    case 3: return .writeEncryptionRequired
    default: return nil
    }
  }

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
    default: return .success
    }
  }
}

extension Data {
  func toFlutterBytes() -> FlutterStandardTypedData {
    FlutterStandardTypedData(bytes: self)
  }
}
