//
//  UniversalBleFilterUtil.swift
//  universal_ble
//
//  Created by Rohit Sangwan on 23/08/24.
//

import CoreBluetooth
import Foundation

public class UniversalBleFilterUtil {
    private var scanFilter: UniversalScanFilter?
    private var serviceFilters: Set<String> = []
    private var serviceDataFilters: Set<String> = []

    /// Single entry point for the filter state.
    ///
    /// Pass `nil` when CoreBluetooth applies the filter itself
    /// (`scanForPeripherals(withServices:)`), which makes [filterDevice] accept
    /// every peripheral. The UUID sets are normalised to the 128-bit lowercase
    /// form CoreBluetooth does not guarantee, and derived here so they cannot
    /// drift from [scanFilter].
    func configure(scanFilter: UniversalScanFilter?) {
        self.scanFilter = scanFilter
        serviceFilters = Set(scanFilter?.withServices.map { normalize(uuid: $0) } ?? [])
        serviceDataFilters = Set(scanFilter?.withServiceData.map { normalize(uuid: $0) } ?? [])
    }

    /// Expands a short UUID to the canonical 128-bit lowercase form the advertised
    /// UUIDs are normalised to before comparison.
    private func normalize(uuid: String) -> String {
        CBUUID(string: uuid).uuid128Str
    }

    func filterDevice(name: String?, manufacturerData: UniversalManufacturerData?, services: [CBUUID]?, serviceData: [CBUUID]? = nil) -> Bool {
        guard let filter = scanFilter else {
            return true
        }

        // The conditions are in OR relation. Each check below is a strict
        // predicate answering "does this dimension match?", so an unfiltered
        // dimension contributes nothing and needs no guard of its own.
        let hasAnyFilter = !filter.withNamePrefix.isEmpty ||
            !serviceFilters.isEmpty ||
            !serviceDataFilters.isEmpty ||
            !filter.withManufacturerData.isEmpty
        if !hasAnyFilter {
            return true
        }

        return isNameMatchingFilters(filter: filter, name: name) ||
            isServicesMatchingFilters(services: services) ||
            isServiceDataMatchingFilters(serviceData: serviceData) ||
            isManufacturerDataMatchingFilters(scanFilter: filter, msd: manufacturerData)
    }

    func isNameMatchingFilters(filter: UniversalScanFilter, name: String?) -> Bool {
        guard let name = name, !name.isEmpty else {
            return false
        }

        return filter.withNamePrefix.compactMap { $0 }.contains { name.hasPrefix($0) }
    }
    /// Compared as 128-bit strings: CoreBluetooth reports a 16-bit advertised
    /// service UUID as its short form, which is not equal to the full form the
    /// Dart layer sends.
    func isServicesMatchingFilters(services: [CBUUID]?) -> Bool {
        guard let services = services, !services.isEmpty else {
            return false
        }

        return !Set(services.map { $0.uuid128Str }).isDisjoint(with: serviceFilters)
    }

    /// Matches a device by the Service Data it advertises (the `0x16`/`0x20`/`0x21`
    /// advertising data types).
    ///
    /// This is a different set from the advertised service UUID lists matched by
    /// [isServicesMatchingFilters]: beacons such as Eddystone (`0xFEAA`) or the
    /// ATC_MiThermometer (`0x181A`) carry the UUID only inside their Service Data.
    func isServiceDataMatchingFilters(serviceData: [CBUUID]?) -> Bool {
        guard let serviceData = serviceData, !serviceData.isEmpty else {
            return false
        }

        return !Set(serviceData.map { $0.uuid128Str }).isDisjoint(with: serviceDataFilters)
    }

    func isManufacturerDataMatchingFilters(scanFilter: UniversalScanFilter, msd: UniversalManufacturerData?) -> Bool {
        guard let msd = msd else {
            return false
        }

        for filter in scanFilter.withManufacturerData.compactMap({ $0 }) {
            let companyIdentifier: Int64 = filter.companyIdentifier
            if msd.companyIdentifier == companyIdentifier && findData(find: filter.payloadPrefix?.toData(), inData: msd.data.toData(), usingMask: filter.payloadMask?.toData()) {
                return true
            }
        }
        return false
    }

    func findData(find: Data?, inData data: Data, usingMask mask: Data?) -> Bool {
        if let find = find {
            // If mask is null, use a default mask of all 1s
            let mask = mask ?? Data(repeating: 0xFF, count: find.count)

            // Ensure find & mask are same length
            guard find.count == mask.count else {
                return false
            }

            for i in 0 ..< find.count {
                // Perform bitwise AND with mask and then compare
                if (find[i] & mask[i]) != (data[i] & mask[i]) {
                    return false
                }
            }
        }
        return true
    }
}

extension UniversalScanFilter {
    var usesCustomFilters: Bool {
        // Service Data matching cannot be expressed as a CoreBluetooth filter:
        // `scanForPeripherals(withServices:)` matches advertised service UUIDs
        // only, so a device carrying the UUID inside its Service Data would never
        // be delivered to the app. Scan with no service filter and match in
        // software instead — the caller opted into the extra battery cost.
        return !withManufacturerData.isEmpty || !withNamePrefix.isEmpty || !withServiceData.isEmpty
    }
}
