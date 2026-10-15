//
//  UniversalBleFilterUtil.swift
//  universal_ble
//
//  Created by Rohit Sangwan on 23/08/24.
//

import CoreBluetooth
import Foundation

public class UniversalBleFilterUtil {
    var scanFilter: UniversalScanFilter?
    var scanFilterServicesUUID: [CBUUID] = []

    /// Service Data UUIDs to match, normalised to 128-bit lowercase form.
    var scanFilterServiceDataUUID: [String] = []

    func filterDevice(name: String?, manufacturerData: UniversalManufacturerData?, services: [CBUUID]?, serviceData: [CBUUID]? = nil) -> Bool {
        guard let filter = scanFilter else {
            return true
        }

        let hasNamePrefixFilter = !filter.withNamePrefix.isEmpty
        let hasServiceFilter = !filter.withServices.isEmpty
        let hasServiceDataFilter = !filter.withServiceData.isEmpty
        let hasManufacturerDataFilter = !filter.withManufacturerData.isEmpty

        // If there is no filter at all, then allow device
        if !hasNamePrefixFilter && !hasServiceFilter && !hasServiceDataFilter && !hasManufacturerDataFilter {
            return true
        }

        // Else check one of the filter passes
        return hasNamePrefixFilter && isNameMatchingFilters(filter: filter, name: name) ||
            hasServiceFilter && isServicesMatchingFilters(services: services) ||
            hasServiceDataFilter && isServiceDataMatchingFilters(serviceData: serviceData) ||
            hasManufacturerDataFilter && isManufacturerDataMatchingFilters(scanFilter: filter, msd: manufacturerData)
    }

    func isNameMatchingFilters(filter: UniversalScanFilter, name: String?) -> Bool {
        let prefixFilters = filter.withNamePrefix.compactMap { $0 }.filter { !$0.isEmpty }

        guard !prefixFilters.isEmpty else {
            return true
        }

        guard let name = name, !name.isEmpty else {
            return false
        }

        return prefixFilters.contains { name.hasPrefix($0) }
    }

    func isServicesMatchingFilters(services: [CBUUID]?) -> Bool {
        // Compared as 128-bit strings: CoreBluetooth reports a 16-bit advertised
        // service UUID as its short form, which is not equal to the full form the
        // Dart layer sends.
        let serviceFilters = Set(scanFilterServicesUUID.map { $0.uuid128Str })

        guard !serviceFilters.isEmpty else {
            return true
        }

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
        let serviceDataFilters = Set(scanFilterServiceDataUUID)

        guard !serviceDataFilters.isEmpty else {
            return true
        }

        guard let serviceData = serviceData, !serviceData.isEmpty else {
            return false
        }

        return !Set(serviceData.map { $0.uuid128Str }).isDisjoint(with: serviceDataFilters)
    }

    func isManufacturerDataMatchingFilters(scanFilter: UniversalScanFilter, msd: UniversalManufacturerData?) -> Bool {
        let filters = scanFilter.withManufacturerData.compactMap { $0 }
        if filters.isEmpty {
            return true
        }

        guard let msd = msd else {
            return false
        }

        for filter in filters {
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
