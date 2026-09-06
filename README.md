# swift-fit-health-kit

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

## Sample resampling policy

HealthKit returns route, heart-rate, distance, speed, cadence, and power data as independent time series. FIT record messages instead contain the measurements associated with one timestamp, so the package deterministically resamples those series before encoding:

- Route timestamps form the FIT record timeline when a route exists. This preserves recorded coordinates and does not invent GPS locations.
- Without a route, the timeline is the sorted, deduplicated union of timestamps from every available quantity series. This preserves power-only, cadence-only, and other indoor workouts.
- Heart rate, speed, cadence, and power use the latest observation at or before a record timestamp. Future observations are never copied backward. Carry-forward is limited to `1.5 ×` the median sampling interval, bounded to 2–10 seconds, so sensor dropouts remain gaps.
- HealthKit distance intervals are first accumulated into cumulative distance. Cumulative distance is then linearly interpolated between known observations; it is never extrapolated after the final observation or allowed to decrease.
- Samples outside the workout interval, duplicate timestamps, and non-finite values are removed before resampling.
- Native speed is preferred while fresh. Otherwise speed is derived from consecutive interpolated cumulative-distance values.

This policy is covered by deterministic tests for future-value leakage, sensor gaps, power-only timelines, distance interpolation, sorting, clipping, and deduplication. Real HealthKit workout fixtures and validation with an independent FIT consumer remain recommended for integration-level verification.

FIT timestamp compression is deliberately disabled for the current timestamp-first record definition.
