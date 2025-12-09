import CoreBluetooth
import Foundation

#if os(iOS)
    import Flutter
#elseif os(OSX)
    import FlutterMacOS
#endif

/// Handles asynchronous service discovery for a BLE peripheral.
/// Manages the complete discovery flow: services -> characteristics -> descriptors
class UniversalBleAsyncServiceDiscovery: NSObject {
    private let peripheral: CBPeripheral
    private let deviceId: String
    private let completion: (Result<[UniversalBleService], Error>) -> Void
    private var discoveredServicesProgressMap: [UniversalBleService] = []
    private var discoveredDescriptorsSet: Set<String> = []
    private var expectedCharacteristicsCountMap: [String: Int] = [:]
    private var isDiscoveryInProgress = false
    private var withDescriptors: Bool

    init(peripheral: CBPeripheral, deviceId: String, withDescriptors: Bool, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
        self.peripheral = peripheral
        self.deviceId = deviceId
        self.completion = completion
        self.withDescriptors = withDescriptors
        super.init()
    }

    /// Starts the service discovery process
    func startDiscovery() {
        guard !isDiscoveryInProgress else {
            print("Service discovery already in progress for device: \(deviceId)")
            return
        }
        isDiscoveryInProgress = true

        // Check if services are already cached
        if let cachedServices = peripheral.services, !cachedServices.isEmpty {
            handleServicesDiscovered(cachedServices)
        } else {
            peripheral.discoverServices(nil)
        }
    }

    /// Cleans up discovery state
    func cleanup() {
        isDiscoveryInProgress = false
        discoveredServicesProgressMap.removeAll()
        discoveredDescriptorsSet.removeAll()
        expectedCharacteristicsCountMap.removeAll()
    }

    private func handleServicesDiscovered(_ services: [CBService]) {
        discoveredServicesProgressMap = services.map { UniversalBleService(uuid: $0.uuid.uuidString, characteristics: nil) }
        discoveredDescriptorsSet = Set<String>()
        expectedCharacteristicsCountMap = [:]

        // Discover characteristics for each service
        for service in services {
            if let cachedChar = service.characteristics, !cachedChar.isEmpty {
                // Characteristics already cached, process them
                handleCharacteristicsDiscovered(for: service)
            } else {
                // Need to discover characteristics
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    private func handleCharacteristicsDiscovered(for service: CBService) {
        let serviceUuid = service.uuid.uuidString
        guard let characteristics = service.characteristics else {
            // Service has no characteristics, mark as complete
            expectedCharacteristicsCountMap[serviceUuid] = 0
            if let index = discoveredServicesProgressMap.firstIndex(where: { $0.uuid == serviceUuid }) {
                discoveredServicesProgressMap[index] = UniversalBleService(uuid: serviceUuid, characteristics: [])
            }
            checkAndCompleteDiscovery()
            return
        }

        // Store expected characteristic count for this service
        expectedCharacteristicsCountMap[serviceUuid] = characteristics.count

        // If no characteristics, mark service as complete
        if characteristics.isEmpty {
            if let index = discoveredServicesProgressMap.firstIndex(where: { $0.uuid == serviceUuid }) {
                discoveredServicesProgressMap[index] = UniversalBleService(uuid: serviceUuid, characteristics: [])
            }
            checkAndCompleteDiscovery()
            return
        }

        if withDescriptors {
            for characteristic in characteristics {
                if let cachedDescriptors = characteristic.descriptors, !cachedDescriptors.isEmpty {
                    handleDescriptorsDiscovered(for: characteristic)
                } else {
                    peripheral.discoverDescriptors(for: characteristic)
                }
            }
        } else {
            if let index = discoveredServicesProgressMap.firstIndex(where: { $0.uuid == serviceUuid }) {
                discoveredServicesProgressMap[index] = UniversalBleService(
                    uuid: serviceUuid,
                    characteristics: characteristics.map {
                        UniversalBleCharacteristic(
                            uuid: $0.uuid.uuidString,
                            properties: $0.properties.toCharacteristicProperty,
                            descriptors: []
                        )
                    }
                )
            }
            checkAndCompleteDiscovery()
        }
    }

    private func handleDescriptorsDiscovered(for characteristic: CBCharacteristic) {
        guard let service = characteristic.service else {
            return
        }

        let serviceUuid = service.uuid.uuidString
        let characteristicUuid = characteristic.uuid.uuidString
        let characteristicKey = "\(serviceUuid):\(characteristicUuid)"

        // Mark this characteristic's descriptors as discovered
        discoveredDescriptorsSet.insert(characteristicKey)

        // Get expected characteristic count for this service
        guard let expectedCount = expectedCharacteristicsCountMap[serviceUuid] else {
            return
        }

        // Check if all characteristics for this service have had their descriptors discovered
        guard let allCharacteristics = service.characteristics else {
            return
        }

        let discoveredCount = allCharacteristics.filter { char in
            let key = "\(serviceUuid):\(char.uuid.uuidString)"
            return discoveredDescriptorsSet.contains(key)
        }.count

        // Only update the service when all characteristics have descriptors discovered
        if discoveredCount == expectedCount {
            var universalBleCharacteristicsList: [UniversalBleCharacteristic] = []
            for characteristic in allCharacteristics {
                universalBleCharacteristicsList.append(
                    UniversalBleCharacteristic(
                        uuid: characteristic.uuid.uuidString,
                        properties: characteristic.properties.toCharacteristicProperty,
                        descriptors: (characteristic.descriptors ?? []).map { UniversalBleDescriptor(uuid: $0.uuid.uuidString) }
                    )
                )
            }

            if let index = discoveredServicesProgressMap.firstIndex(where: { $0.uuid == serviceUuid }) {
                discoveredServicesProgressMap[index] = UniversalBleService(uuid: serviceUuid, characteristics: universalBleCharacteristicsList)
            }

            checkAndCompleteDiscovery()
        }
    }

    private func checkAndCompleteDiscovery() {
        // Check if all services have been fully discovered (all characteristics with all descriptors)
        guard discoveredServicesProgressMap.allSatisfy({ $0.characteristics != nil }) else {
            return
        }
        completion(.success(discoveredServicesProgressMap))
        cleanup()
    }
}

// These methods are called by the main plugin class when it receives delegate callbacks
extension UniversalBleAsyncServiceDiscovery {
    func handleDidDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        guard error == nil else {
            completion(.failure(error!))
            cleanup()
            return
        }
        guard let services = peripheral.services else {
            completion(.success([]))
            cleanup()
            return
        }
        handleServicesDiscovered(services)
    }

    func handleDidDiscoverCharacteristicsFor(_: CBPeripheral, service: CBService, error: Error?) {
        guard error == nil else {
            completion(.failure(error!))
            cleanup()
            return
        }
        handleCharacteristicsDiscovered(for: service)
    }

    func handleDidDiscoverDescriptorsFor(_: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            completion(.failure(error!))
            cleanup()
            return
        }
        handleDescriptorsDiscovered(for: characteristic)
    }
}
