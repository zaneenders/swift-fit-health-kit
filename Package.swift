// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SwiftFitHealthKit",
  platforms: [
    .iOS(.v17),
  ],
  products: [
    .library(name: "SwiftFitHealthKit", targets: ["SwiftFitHealthKit"]),
  ],
  dependencies: [
    .package(path: "../../../swift-fit"),
  ],
  targets: [
    .target(
      name: "SwiftFitHealthKit",
      dependencies: [
        .product(name: "SwiftFit", package: "swift-fit"),
        .product(name: "SwiftFitActivity", package: "swift-fit"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "SwiftFitHealthKitTests",
      dependencies: [
        "SwiftFitHealthKit",
        .product(name: "SwiftFit", package: "swift-fit"),
        .product(name: "SwiftFitActivity", package: "swift-fit"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
  ]
)
