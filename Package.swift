// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "swift-fit-health-kit",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "SwiftFitHealthKit", targets: ["SwiftFitHealthKit"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/zaneenders/swift-fit.git",
      revision: "8ac03654f4b46eaa4a22e819a6c4c193e08517a7"
    )
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
