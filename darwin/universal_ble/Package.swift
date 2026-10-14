// swift-tools-version: 5.9
// Swift Package Manager support for the Flutter `universal_ble` plugin (darwin shared sources).

import PackageDescription

let package = Package(
  name: "universal_ble",
  platforms: [
    .iOS("13.1"),
    .macOS("10.15"),
  ],
  products: [
    // If the plugin name contains `_`, the library name must use `-`.
    .library(name: "universal-ble", targets: ["universal_ble"]),
  ],
  dependencies: [
    // Flutter injects this local package when SwiftPM integration is enabled.
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "universal_ble",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      cSettings: [
        // Expose any public headers (if/when added) under the SPM include directory.
        .headerSearchPath("include/universal_ble")
      ]
    ),
  ]
)

