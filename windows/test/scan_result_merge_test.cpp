// Unit tests for the pure scan-result merge/delivery decisions used by
// UniversalBlePlugin::PushUniversalScanResult. They cover the Windows
// scan-response fix: a scan response must reach the caller, a sparse response
// must not evict cached data, and non-connectable advertisers must stay out.

#include "scan_result_merge.h"

#include <iostream>

using universal_ble::PlanScanBackfill;
using universal_ble::ScanBackfillPlan;
using universal_ble::ScanFieldPresence;
using universal_ble::ShouldDeliverScanResult;
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

ScanFieldPresence Presence(bool name, bool services, bool service_data) {
  ScanFieldPresence presence;
  presence.name = name;
  presence.services = services;
  presence.service_data = service_data;
  return presence;
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
    const ScanBackfillPlan plan =
        PlanScanBackfill(Presence(/*name=*/true, /*services=*/false,
                                  /*service_data=*/false),
                         Presence(/*name=*/false, /*services=*/true,
                                  /*service_data=*/false));
    CHECK(plan.services);
    CHECK(!plan.name);
    CHECK(ShouldUpdateScanResult(plan, /*is_scan_response=*/true));
  }

  // A sparse scan response must not evict cached serviceData either.
  {
    const ScanBackfillPlan plan = PlanScanBackfill(
        Presence(true, false, false), Presence(false, false, true));
    CHECK(plan.service_data);
    CHECK(ShouldUpdateScanResult(plan, true));
  }

  // A packet that already carries a field is not backfilled from the cache.
  {
    const ScanBackfillPlan plan = PlanScanBackfill(Presence(true, true, true),
                                                   Presence(true, true, true));
    CHECK(!plan.name);
    CHECK(!plan.services);
    CHECK(!plan.service_data);
  }

  // Nothing to copy from an empty cache: the packet keeps its own fields.
  {
    const ScanBackfillPlan plan = PlanScanBackfill(
        Presence(true, false, false), Presence(false, false, false));
    CHECK(!plan.services);
    CHECK(!plan.service_data);
  }

  // A scan response is an update on its own, even with nothing to backfill.
  CHECK(ShouldUpdateScanResult(ScanBackfillPlan{}, /*is_scan_response=*/true));

  // A connectable advertisement with nothing new is deduplicated.
  CHECK(
      !ShouldUpdateScanResult(ScanBackfillPlan{}, /*is_scan_response=*/false));

  // Delivery gate: connectable packets always pass.
  CHECK(ShouldDeliverScanResult(/*is_connectable=*/true,
                                /*is_scan_response=*/false,
                                /*address_heard_connectable=*/false));

  // An answered scan request passes only for an address heard connectable.
  CHECK(ShouldDeliverScanResult(false, true, true));
  CHECK(!ShouldDeliverScanResult(false, true, false));

  // A non-connectable packet that is not a scan response never passes.
  CHECK(!ShouldDeliverScanResult(false, false, true));

  return 0;
}
