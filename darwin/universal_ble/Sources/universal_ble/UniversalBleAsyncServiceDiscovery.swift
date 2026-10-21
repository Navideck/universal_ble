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
    /// The services in the peripheral's order, held so that their identities
    /// stay unique while `progress` keys on them. Progress kept by UUID string
    /// never completed for a peripheral with two services of one UUID.
    private var discoveredServices: [CBService] = []
    private var progress: UniversalBleDiscoveryProgress<ObjectIdentifier, ObjectIdentifier>?
    private var isDiscoveryInProgress = false
    private var hasCompleted = false
    private var withDescriptors: Bool
    private var timeoutWorkItem: DispatchWorkItem?
    private let timeoutSeconds: TimeInterval

    /// Discovery that has not completed after the timeout fails, so that it cannot hold back
    /// later calls for the same device.
    static let defaultTimeoutSeconds: TimeInterval = 10.0

    /// The discovery timeout for these options: `AppleDiscoverServicesOptions.timeoutMillis`,
    /// else `defaultTimeoutSeconds`.
    static func timeoutSeconds(for platformConfig: DiscoverServicesPlatformConfig?) -> TimeInterval {
        guard let millis = platformConfig?.apple?.timeoutMillis, millis > 0 else {
            return defaultTimeoutSeconds
        }
        return TimeInterval(millis) / 1000
    }

    init(peripheral: CBPeripheral, deviceId: String, withDescriptors: Bool, timeoutSeconds: TimeInterval = UniversalBleAsyncServiceDiscovery.defaultTimeoutSeconds, completion: @escaping (Result<[UniversalBleService], Error>) -> Void) {
        self.peripheral = peripheral
        self.deviceId = deviceId
        self.completion = completion
        self.withDescriptors = withDescriptors
        self.timeoutSeconds = timeoutSeconds
        super.init()
    }

    /// Starts the service discovery process
    func startDiscovery() {
        guard !isDiscoveryInProgress, !hasCompleted else {
            UniversalBleLogger.shared.logWarning("Service discovery already in progress for device: \(deviceId)")
            return
        }
        isDiscoveryInProgress = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            UniversalBleLogger.shared.logError("Service discovery timed out for device: \(self.deviceId)")
            self.completeWith(result: .failure(createFlutterError(code: .failed, message: "Service discovery timed out for device: \(self.deviceId)")))
        }
        self.timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)

        // Check if services are already cached
        let safeServices = peripheral.safeServices
        if safeServices.hasForeign {
            failForStaleGattCache(location: "cached services", foreignClassNames: safeServices.foreignClassNames)
            return
        }
        if let cachedServices = safeServices.attributes, !cachedServices.isEmpty {
            handleServicesDiscovered(cachedServices)
        } else {
            peripheral.discoverServices(nil)
        }
    }

    /// Cancels the service discovery and fails completion
    func cancel(error: Error) {
        completeWith(result: .failure(error))
    }

    /// Fails discovery due to stale CoreBluetooth GATT cache holding foreign classes in attribute arrays
    func failForStaleGattCache(location: String, foreignClassNames: [String]) {
        let message = "Stale GATT cache: \(foreignClassNames.count) attribute(s) of unexpected type [\(foreignClassNames.joined(separator: ", "))] in \(location) of peripheral \(deviceId); iOS reads the device's attribute table again after Bluetooth is turned off and on or device is forgotten in Settings"
        UniversalBleLogger.shared.logError(message)
        completeWith(result: .failure(createFlutterError(code: .failed, message: message)))
    }

    /// Cleans up discovery state
    func cleanup() {
        isDiscoveryInProgress = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        discoveredServices.removeAll()
        progress = nil
    }

    private func completeWith(result: Result<[UniversalBleService], Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(result)
    }

    private func handleServicesDiscovered(_ services: [CBService]) {
        discoveredServices = services
        progress = UniversalBleDiscoveryProgress<ObjectIdentifier, ObjectIdentifier>(
            services: services.map { ObjectIdentifier($0) },
            withDescriptors: withDescriptors
        )

        // If no services, complete discovery immediately
        guard !services.isEmpty else {
            checkForDiscoveryCompletion()
            return
        }

        // Discover characteristics for each service
        for service in services {
            let safeChars = service.safeCharacteristics
            if safeChars.hasForeign {
                failForStaleGattCache(
                    location: "cached characteristics of service \(service.uuid.uuidString)",
                    foreignClassNames: safeChars.foreignClassNames
                )
                return
            }
            if let cachedChar = safeChars.attributes, !cachedChar.isEmpty {
                // Characteristics already cached, process them
                processCharacteristicsForService(service)
            } else {
                // Need to discover characteristics
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    private func processCharacteristicsForService(_ service: CBService) {
        let safeChars = service.safeCharacteristics
        if safeChars.hasForeign {
            failForStaleGattCache(
                location: "characteristics of service \(service.uuid.uuidString)",
                foreignClassNames: safeChars.foreignClassNames
            )
            return
        }
        // A service with no characteristics (nil or empty) is complete as it is.
        let characteristics = safeChars.attributes ?? []

        // The service is found by its identity, never by its UUID, so a
        // second service with the same UUID is its own entry.
        // A service this discovery was not started with is ignored.
        guard progress?.characteristicsDiscovered(
            for: ObjectIdentifier(service),
            characteristics.map { ObjectIdentifier($0) }
        ) == true else {
            return
        }

        if withDescriptors {
            for characteristic in characteristics {
                let safeDescs = characteristic.safeDescriptors
                if safeDescs.hasForeign {
                    failForStaleGattCache(
                        location: "cached descriptors of characteristic \(characteristic.uuid.uuidString)",
                        foreignClassNames: safeDescs.foreignClassNames
                    )
                    return
                }
                if let cachedDescriptors = safeDescs.attributes, !cachedDescriptors.isEmpty {
                    handleDescriptorsDiscovered(for: characteristic)
                } else {
                    peripheral.discoverDescriptors(for: characteristic)
                }
            }
        }
        checkForDiscoveryCompletion()
    }

    private func handleDescriptorsDiscovered(for characteristic: CBCharacteristic) {
        // By the characteristic's identity, never by
        // "service UUID:characteristic UUID".
        progress?.descriptorsDiscovered(for: ObjectIdentifier(characteristic))
        checkForDiscoveryCompletion()
    }

    private func checkForDiscoveryCompletion() {
        // Check if all services have been fully discovered (all characteristics with all descriptors)
        guard let progress = progress, progress.isComplete else {
            return
        }
        // The result is built through the safe accessors too, so a stale
        // GATT cache still fails discovery here rather than trapping.
        var services: [UniversalBleService] = []
        for service in discoveredServices {
            let safeChars = service.safeCharacteristics
            if safeChars.hasForeign {
                failForStaleGattCache(
                    location: "characteristics of service \(service.uuid.uuidString)",
                    foreignClassNames: safeChars.foreignClassNames
                )
                return
            }
            var characteristics: [UniversalBleCharacteristic] = []
            for characteristic in safeChars.attributes ?? [] {
                var descriptors: [UniversalBleDescriptor] = []
                if withDescriptors {
                    let safeDescs = characteristic.safeDescriptors
                    if safeDescs.hasForeign {
                        failForStaleGattCache(
                            location: "descriptors of characteristic \(characteristic.uuid.uuidString)",
                            foreignClassNames: safeDescs.foreignClassNames
                        )
                        return
                    }
                    descriptors = (safeDescs.attributes ?? []).map { UniversalBleDescriptor(uuid: $0.uuid.uuidString) }
                }
                characteristics.append(
                    UniversalBleCharacteristic(
                        uuid: characteristic.uuid.uuidString,
                        properties: characteristic.properties.toCharacteristicProperty,
                        descriptors: descriptors
                    )
                )
            }
            services.append(UniversalBleService(uuid: service.uuid.uuidString, characteristics: characteristics))
        }
        completeWith(result: .success(services))
    }
}

// These methods are called by the main plugin class when it receives delegate callbacks
extension UniversalBleAsyncServiceDiscovery {
    func handleDidDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        guard error == nil else {
            completeWith(result: .failure(error!))
            return
        }
        let safeServices = peripheral.safeServices
        if safeServices.hasForeign {
            failForStaleGattCache(location: "services", foreignClassNames: safeServices.foreignClassNames)
            return
        }
        guard let services = safeServices.attributes else {
            completeWith(result: .success([]))
            return
        }
        handleServicesDiscovered(services)
    }

    func handleDidDiscoverCharacteristicsFor(_: CBPeripheral, service: CBService, error: Error?) {
        guard (service as AnyObject) is CBService else {
            let actual = NSStringFromClass(type(of: service as AnyObject))
            failForStaleGattCache(
                location: "didDiscoverCharacteristicsFor (delegate received \(actual))",
                foreignClassNames: [actual]
            )
            return
        }
        guard error == nil else {
            completeWith(result: .failure(error!))
            return
        }
        processCharacteristicsForService(service)
    }

    func handleDidDiscoverDescriptorsFor(_: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard (characteristic as AnyObject) is CBCharacteristic else {
            let actual = NSStringFromClass(type(of: characteristic as AnyObject))
            failForStaleGattCache(
                location: "didDiscoverDescriptorsFor (delegate received \(actual))",
                foreignClassNames: [actual]
            )
            return
        }
        guard error == nil else {
            completeWith(result: .failure(error!))
            return
        }
        handleDescriptorsDiscovered(for: characteristic)
    }
}
