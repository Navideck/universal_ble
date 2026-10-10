#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLE_SCAN_RESULT_MERGE_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLE_SCAN_RESULT_MERGE_H_

namespace universal_ble {

// Which fields a scan packet actually carries. A field counts as present only
// when it holds a usable, non-empty value: the advertisement watcher sets
// `services` unconditionally, so a null check alone cannot tell "carries an
// empty list" from "carries nothing".
struct ScanFieldPresence {
  bool name = false;
  bool is_paired = false;
  bool manufacturer_data = false;
  bool services = false;
  bool service_data = false;
};

// Cached fields that must be copied into an incoming packet so that a newer,
// but sparser, packet does not drop data the cache already holds.
struct ScanBackfillPlan {
  bool name = false;
  bool is_paired = false;
  bool manufacturer_data = false;
  bool services = false;
  bool service_data = false;
};

// Backfill a field when the incoming packet misses it but the cache has it.
inline bool ShouldBackfillScanField(bool incoming_present,
                                    bool cached_present) {
  return !incoming_present && cached_present;
}

inline ScanBackfillPlan PlanScanBackfill(const ScanFieldPresence &incoming,
                                         const ScanFieldPresence &cached) {
  ScanBackfillPlan plan;
  plan.name = ShouldBackfillScanField(incoming.name, cached.name);
  plan.is_paired =
      ShouldBackfillScanField(incoming.is_paired, cached.is_paired);
  plan.manufacturer_data = ShouldBackfillScanField(incoming.manufacturer_data,
                                                   cached.manufacturer_data);
  plan.services = ShouldBackfillScanField(incoming.services, cached.services);
  plan.service_data =
      ShouldBackfillScanField(incoming.service_data, cached.service_data);
  return plan;
}

// A packet is an update when it backfills cached data, or when it is the answer
// to the scan request the host sent: a scan response is newer by itself, even
// when no cached field could be copied into it. Otherwise the cache-dedup early
// return drops it.
inline bool ShouldUpdateScanResult(const ScanBackfillPlan &plan,
                                   bool is_scan_response) {
  return plan.name || plan.is_paired || plan.manufacturer_data ||
         plan.services || plan.service_data || is_scan_response;
}

// A packet may be handed to the caller when it advertised connectably, or when
// it is an answered scan request for an address already seen connectably. This
// keeps beacons and other non-connectable advertisers out.
inline bool ShouldDeliverScanResult(bool is_connectable, bool is_scan_response,
                                    bool address_heard_connectable) {
  return is_connectable || (is_scan_response && address_heard_connectable);
}

}  // namespace universal_ble

#endif  // FLUTTER_PLUGIN_UNIVERSAL_BLE_SCAN_RESULT_MERGE_H_
