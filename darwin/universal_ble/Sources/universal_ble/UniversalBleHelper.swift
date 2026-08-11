//
//  UniversalBleHelper.swift
//  universal_ble
//
//  Created by Rohit Sangwan on 25/10/23.
//

import CoreBluetooth
import Foundation
#if os(iOS)
    import Flutter
#elseif os(OSX)
    import FlutterMacOS
#endif

extension CBCharacteristicProperties {
    var toCharacteristicProperty: [CharacteristicProperty] {
        var properties = [CharacteristicProperty]()
        if contains(.broadcast) {
            properties.append(.broadcast)
        }
        if contains(.read) {
            properties.append(.read)
        }
        if contains(.writeWithoutResponse) {
            properties.append(.writeWithoutResponse)
        }
        if contains(.write) {
            properties.append(.write)
        }
        if contains(.notify) {
            properties.append(.notify)
        }
        if contains(.indicate) {
            properties.append(.indicate)
        }
        if contains(.authenticatedSignedWrites) {
            properties.append(.authenticatedSignedWrites)
        }
        if contains(.extendedProperties) {
            properties.append(.extendedProperties)
        }
        return properties
    }
}

extension CBManagerState {
    func toAvailabilityState() -> AvailabilityState {
        switch self {
        case .unknown:
            return .unknown
        case .resetting:
            return .resetting
        case .unsupported:
            return .unsupported
        case .unauthorized:
            return .unauthorized
        case .poweredOff:
            return .poweredOff
        case .poweredOn:
            return .poweredOn
        @unknown default:
            return .unknown
        }
    }
}

extension CBPeripheralState {
    var toBleConnectionState: BleConnectionState {
        switch self {
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .disconnecting:
            return .disconnecting
        case .disconnected:
            return .disconnected
        @unknown default:
            return .disconnected
        }
    }
}

/// Maps string error codes to UniversalBleErrorCode enum
func mapErrorCodeToEnum(_ code: String) -> UniversalBleErrorCode {
    switch code.lowercased() {
    case "notsupported", "not_supported":
        return .notSupported
    case "notimplemented", "not_implemented":
        return .notImplemented
    case "channel-error", "channelerror":
        return .channelError
    case "failed":
        return .failed
    case "devicedisconnected", "device_disconnected":
        return .deviceDisconnected
    case "illegalargument", "illegal_argument":
        return .illegalArgument
    case "invalidaction", "invalid_action":
        return .invalidAction
    case "readfailed", "read_failed":
        return .readFailed
    case "devicenotfound", "device_not_found":
        return .deviceNotFound
    case "servicenotfound", "service_not_found":
        return .serviceNotFound
    case "characteristicnotfound", "characteristic_not_found":
        return .characteristicNotFound
    case "invalidserviceuuid", "invalid_service_uuid":
        return .invalidServiceUuid
    case "characteristicdoesnotsupportread":
        return .characteristicDoesNotSupportRead
    case "characteristicdoesnotsupportwrite":
        return .characteristicDoesNotSupportWrite
    case "characteristicdoesnotsupportwritewithoutresponse":
        return .characteristicDoesNotSupportWriteWithoutResponse
    case "characteristicdoesnotsupportnotify":
        return .characteristicDoesNotSupportNotify
    case "characteristicdoesnotsupportindicate":
        return .characteristicDoesNotSupportIndicate
    default:
        return .unknownError
    }
}

/// Creates a PigeonError with the error code enum in details
func createFlutterError(
    code: UniversalBleErrorCode,
    message: String? = nil,
    details: String? = nil
) -> PigeonError {
    // Pass the enum's rawValue (Int) in code as string, and enum name in details
    return PigeonError(
        code: code.rawValue.description,
        message: message,
        details: details ?? code.rawValue
    )
}

extension Error {
    func toFlutterError() -> PigeonError {
        let nsError = self as NSError
        let errorCode: String = .init(nsError.code)
        let errorDescription: String = nsError.localizedDescription
        let mappedCode = mapErrorCodeToEnum(errorCode)
        return createFlutterError(code: mappedCode, message: errorDescription, details: errorCode)
    }
}

public extension CBUUID {
    var uuidStr: String {
        uuidString.lowercased()
    }
}

public extension CBPeripheral {
    var uuid: UUID {
        identifier
    }

    func getCharacteristic(_ characteristic: String, of service: String) -> CBCharacteristic? {
        let GSS_SUFFIX = "0000-1000-8000-00805f9b34fb"
        let s = services?.first {
            $0.uuid.uuidStr.lowercased() == service.lowercased() || service.lowercased() == "0000\($0.uuid.uuidStr)-\(GSS_SUFFIX)".lowercased()
        }
        let c = s?.characteristics?.first {
            $0.uuid.uuidStr.lowercased() == characteristic.lowercased() || characteristic.lowercased() == "0000\($0.uuid.uuidStr)-\(GSS_SUFFIX)".lowercased()
        }
        return c
    }

    func getDescriptor(_ descriptor: String, for characteristic: String, of service: String) -> CBDescriptor? {
        let GSS_SUFFIX = "0000-1000-8000-00805f9b34fb"
        guard let c = getCharacteristic(characteristic, of: service) else { return nil }
        return c.descriptors?.first {
            $0.uuid.uuidStr.lowercased() == descriptor.lowercased() || descriptor.lowercased() == "0000\($0.uuid.uuidStr)-\(GSS_SUFFIX)".lowercased()
        }
    }

    func setNotifiable(_ bleInputProperty: String, for characteristic: String, of service: String) {
        guard let characteristic = getCharacteristic(characteristic, of: service) else {
            return
        }
        setNotifyValue(bleInputProperty != "disabled", for: characteristic)
    }
}

extension FlutterStandardTypedData {
    func toData() -> Data {
        return Data(data)
    }
}

// Future protocol and implementations
protocol DeviceFuture {
    var deviceId: String { get }
    func fail(with error: Error)
}

extension Array where Element: DeviceFuture {
    mutating func failAndRemoveAll(matching deviceId: String, with error: Error) {
        removeAll { future in
            if future.deviceId.caseInsensitiveCompare(deviceId) == .orderedSame {
                future.fail(with: error)
                return true
            }
            return false
        }
    }
}

class CharacteristicReadFuture: DeviceFuture {
    let deviceId: String
    let characteristicId: String
    let serviceId: String?
    let result: (Result<FlutterStandardTypedData, Error>) -> Void

    init(deviceId: String, characteristicId: String, serviceId: String?, result: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        self.deviceId = deviceId
        self.characteristicId = characteristicId
        self.serviceId = serviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class CharacteristicWriteFuture: DeviceFuture {
    let deviceId: String
    let characteristicId: String
    let serviceId: String?
    let result: (Result<Void, Error>) -> Void

    init(deviceId: String, characteristicId: String, serviceId: String?, result: @escaping (Result<Void, Error>) -> Void) {
        self.deviceId = deviceId
        self.characteristicId = characteristicId
        self.serviceId = serviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class PendingWriteWithoutResponse: DeviceFuture {
    let deviceId: String
    let characteristic: CBCharacteristic
    let data: Data
    let result: (Result<Void, Error>) -> Void

    init(deviceId: String, characteristic: CBCharacteristic, data: Data, result: @escaping (Result<Void, Error>) -> Void) {
        self.deviceId = deviceId
        self.characteristic = characteristic
        self.data = data
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class CharacteristicNotifyFuture: DeviceFuture {
    let deviceId: String
    let characteristicId: String
    let serviceId: String?
    let result: (Result<Void, Error>) -> Void

    init(deviceId: String, characteristicId: String, serviceId: String?, result: @escaping (Result<Void, Error>) -> Void) {
        self.deviceId = deviceId
        self.characteristicId = characteristicId
        self.serviceId = serviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class DiscoverServicesFuture: DeviceFuture {
    let deviceId: String
    let result: (Result<[UniversalBleService], Error>) -> Void

    init(deviceId: String, result: @escaping (Result<[UniversalBleService], Error>) -> Void) {
        self.deviceId = deviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class RssiReadFuture: DeviceFuture {
    let deviceId: String
    let result: (Result<Int64, Error>) -> Void

    init(deviceId: String, result: @escaping (Result<Int64, Error>) -> Void) {
        self.deviceId = deviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class DescriptorReadFuture: DeviceFuture {
    let deviceId: String
    let descriptorId: String
    let characteristicId: String
    let serviceId: String?
    let result: (Result<FlutterStandardTypedData, Error>) -> Void

    init(deviceId: String, descriptorId: String, characteristicId: String, serviceId: String?, result: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        self.deviceId = deviceId
        self.descriptorId = descriptorId
        self.characteristicId = characteristicId
        self.serviceId = serviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}

class DescriptorWriteFuture: DeviceFuture {
    let deviceId: String
    let descriptorId: String
    let characteristicId: String
    let serviceId: String?
    let result: (Result<Void, Error>) -> Void

    init(deviceId: String, descriptorId: String, characteristicId: String, serviceId: String?, result: @escaping (Result<Void, Error>) -> Void) {
        self.deviceId = deviceId
        self.descriptorId = descriptorId
        self.characteristicId = characteristicId
        self.serviceId = serviceId
        self.result = result
    }

    func fail(with error: Error) {
        result(.failure(error))
    }
}
