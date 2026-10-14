// Unit tests for the pure scan-result merge, update and connectability
// decisions used by UniversalBlePlugin::PushUniversalScanResult. They cover the
// Windows scan-response handling: a scan response must reach the caller, a
// sparse response must not evict cached data, and scan responses preserve
// connectability.

#include "scan_result_merge.h"

#include <iostream>

using universal_ble::DeriveConnectableState;
using universal_ble::PlanScanBackfill;
using universal_ble::ScanBackfillPlan;
using universal_ble::ScanFieldPresence;
using universal_ble::ShouldUpdateScanResult;

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
  // A sparse scan response must not evict the cached service list: the
  // advertisement watcher always sets `services`, so an empty list has to be
  // treated like a missing one.
  {
    const ScanBackfillPlan plan = PlanScanBackfill(
        ScanFieldPresence{.name = true}, ScanFieldPresence{.services = true});
    CHECK(plan.services);
    CHECK(!plan.name);
    CHECK(ShouldUpdateScanResult(plan, /*is_scan_response=*/true,
                                 /*connectable_changed=*/false));
  }

  // A sparse scan response must not evict cached serviceData either.
  {
    const ScanBackfillPlan plan =
        PlanScanBackfill(ScanFieldPresence{.name = true},
                         ScanFieldPresence{.service_data = true});
    CHECK(plan.service_data);
    CHECK(ShouldUpdateScanResult(plan, /*is_scan_response=*/true,
                                 /*connectable_changed=*/false));
  }

  // is_paired and manufacturer_data are backfilled by the same rule.
  {
    const ScanBackfillPlan plan = PlanScanBackfill(
        ScanFieldPresence{}, ScanFieldPresence{.is_paired = true});
    CHECK(plan.is_paired);
    CHECK(!plan.name);
  }
  {
    const ScanBackfillPlan plan = PlanScanBackfill(
        ScanFieldPresence{}, ScanFieldPresence{.manufacturer_data = true});
    CHECK(plan.manufacturer_data);
    CHECK(!plan.services);
  }

  // A packet that already carries a field is not backfilled from the cache.
  {
    const ScanFieldPresence all{.name = true,
                                .is_paired = true,
                                .manufacturer_data = true,
                                .services = true,
                                .service_data = true};
    const ScanBackfillPlan plan = PlanScanBackfill(all, all);
    CHECK(!plan.name);
    CHECK(!plan.is_paired);
    CHECK(!plan.manufacturer_data);
    CHECK(!plan.services);
    CHECK(!plan.service_data);
  }

  // Nothing to copy from an empty cache: the packet keeps its own fields.
  {
    const ScanBackfillPlan plan =
        PlanScanBackfill(ScanFieldPresence{.name = true}, ScanFieldPresence{});
    CHECK(!plan.name);
    CHECK(!plan.is_paired);
    CHECK(!plan.manufacturer_data);
    CHECK(!plan.services);
    CHECK(!plan.service_data);
  }

  // A scan response is an update on its own, even with nothing to backfill.
  CHECK(ShouldUpdateScanResult(ScanBackfillPlan{}, /*is_scan_response=*/true,
                               /*connectable_changed=*/false));

  // A plain packet with nothing new and an unchanged connectable state is
  // deduplicated.
  CHECK(!ShouldUpdateScanResult(ScanBackfillPlan{}, /*is_scan_response=*/false,
                                /*connectable_changed=*/false));

  // A connectable-state change is an update on its own.
  CHECK(ShouldUpdateScanResult(ScanBackfillPlan{}, /*is_scan_response=*/false,
                               /*connectable_changed=*/true));

  // Connectability derivation:
  // Connectable advertisements report connectable.
  CHECK(DeriveConnectableState(/*is_connectable=*/true,
                               /*is_scan_response=*/false,
                               /*address_heard_connectable=*/false));

  // Non-connectable advertisements (e.g. beacons) report non-connectable.
  CHECK(!DeriveConnectableState(/*is_connectable=*/false,
                                /*is_scan_response=*/false,
                                /*address_heard_connectable=*/false));

  // An answered scan request inherits connectable if heard connectable.
  CHECK(DeriveConnectableState(/*is_connectable=*/false,
                               /*is_scan_response=*/true,
                               /*address_heard_connectable=*/true));

  // A scan response for an address never heard connectable reports
  // non-connectable.
  CHECK(!DeriveConnectableState(/*is_connectable=*/false,
                                /*is_scan_response=*/true,
                                /*address_heard_connectable=*/false));

  return 0;
}
