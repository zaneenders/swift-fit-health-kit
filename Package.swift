// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "swift-fit-health-kit",
  platforms: [
    .iOS(.v18),
    .macOS(.v26),
  ],
  products: [
    .library(name: "SwiftFitHealthKit", targets: ["SwiftFitHealthKit"])
  ],
  dependencies: [
    .package(path: "../swift-fit")
  ],
  targets: [
    .target(
      name: "SwiftFitHealthKit",
      dependencies: [
        .product(name: "SwiftFit", package: "swift-fit"),
        .product(name: "SwiftFitActivity", package: "swift-fit"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
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
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
