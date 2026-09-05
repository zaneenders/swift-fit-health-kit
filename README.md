# SwiftFitHealthKit

An iOS-only Swift package that converts HealthKit workouts into Garmin FIT activity files.

The package owns the complete conversion boundary:

1. request HealthKit read authorization;
2. load workout quantities and route locations;
3. merge differently sampled HealthKit series onto a record timeline;
4. encode standard FIT activity, event, record, lap, and session messages;
5. verify the result can be parsed before returning it to the app.

```swift
import HealthKit
import SwiftFitHealthKit

let (data, filename) = try await WorkoutFITExporter.encode(
  workout: workout,
  store: HKHealthStore()
)
```

The lower-level APIs are public for deterministic tests and specialized callers:

- `HealthKitWorkoutLoader`
- `WorkoutSampleMerger`
- `WorkoutFITEncoder`
- `WorkoutExportBundle` and related sample models

FIT timestamp compression is deliberately disabled for the current timestamp-first record definition. See `../../FIT_VALIDATION_PLAN.md` for the interoperability and release gates.
