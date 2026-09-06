import Foundation
import Testing

@testable import SwiftFitHealthKit

@Suite struct WorkoutSampleMergerTests {
  @Test func usesRouteAsTimelineAndDoesNotCopyFutureMeasurementsBackward() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let raw = RawWorkoutSamples(
      heartRates: [
        TimedQuantity(date: start, value: 120),
        TimedQuantity(date: start.addingTimeInterval(10), value: 140),
      ],
      distances: [
        TimedQuantity(date: start, value: 0),
        TimedQuantity(date: start.addingTimeInterval(10), value: 50),
      ],
      speeds: [TimedQuantity(date: start.addingTimeInterval(10), value: 5)],
      cadences: [TimedQuantity(date: start.addingTimeInterval(10), value: 82)],
      powers: [TimedQuantity(date: start.addingTimeInterval(10), value: 245)],
      locations: [
        TimedLocation(date: start, latitude: 40, longitude: -111, altitudeMeters: 1_500),
        TimedLocation(
          date: start.addingTimeInterval(10), latitude: 40.001, longitude: -111.001,
          altitudeMeters: 1_490),
      ]
    )

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(10))

    #expect(samples.count == 2)
    #expect(samples[0].latitude == 40)
    #expect(samples[0].speedMps == nil)
    #expect(samples[0].cadenceRpm == nil)
    #expect(samples[0].powerWatts == nil)
    #expect(samples[1].heartRateBpm == 140)
    #expect(samples[1].speedMps == 5)
    #expect(samples[1].cadenceRpm == 82)
    #expect(samples[1].powerWatts == 245)
  }

  @Test func usesUnionOfEveryQuantityTimelineWithoutRoute() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let raw = RawWorkoutSamples(
      heartRates: [TimedQuantity(date: start, value: 121)],
      distances: [TimedQuantity(date: start.addingTimeInterval(2), value: 10)],
      speeds: [],
      cadences: [TimedQuantity(date: start.addingTimeInterval(3), value: 80)],
      powers: [TimedQuantity(date: start.addingTimeInterval(1), value: 200)],
      locations: [])

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(4))

    #expect(
      samples.map(\.timestamp) == [
        start,
        start.addingTimeInterval(1),
        start.addingTimeInterval(2),
        start.addingTimeInterval(3),
      ])
    #expect(samples[1].powerWatts == 200)
    #expect(samples[3].cadenceRpm == 80)
  }

  @Test func preservesPowerOnlyIndoorWorkoutTimeline() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let powers = (0..<3).map {
      TimedQuantity(date: start.addingTimeInterval(Double($0)), value: Double(200 + $0 * 10))
    }
    let raw = RawWorkoutSamples(
      heartRates: [], distances: [], speeds: [], cadences: [], powers: powers, locations: [])

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(2))

    #expect(samples.count == 3)
    #expect(samples.map(\.powerWatts) == [200, 210, 220])
  }

  @Test func doesNotCarryMeasurementsAcrossSensorGap() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let route = (0...30).map {
      TimedLocation(
        date: start.addingTimeInterval(Double($0)),
        latitude: 40,
        longitude: -111,
        altitudeMeters: nil)
    }
    let raw = RawWorkoutSamples(
      heartRates: [
        TimedQuantity(date: start, value: 120),
        TimedQuantity(date: start.addingTimeInterval(1), value: 122),
        TimedQuantity(date: start.addingTimeInterval(30), value: 140),
      ],
      distances: [], speeds: [], cadences: [], powers: [], locations: route)

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(30))

    #expect(samples[2].heartRateBpm == 122)
    #expect(samples[3].heartRateBpm == 122)
    #expect(samples[4].heartRateBpm == nil)
    #expect(samples[29].heartRateBpm == nil)
    #expect(samples[30].heartRateBpm == 140)
  }

  @Test func interpolatesMonotonicDistanceOntoRouteTimeline() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let route = (0...10).map {
      TimedLocation(
        date: start.addingTimeInterval(Double($0)),
        latitude: 40,
        longitude: -111,
        altitudeMeters: nil)
    }
    let raw = RawWorkoutSamples(
      heartRates: [],
      distances: [TimedQuantity(date: start.addingTimeInterval(10), value: 100)],
      speeds: [], cadences: [], powers: [], locations: route)

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(10))

    #expect(samples.map(\.distanceMeters) == (0...10).map { Optional(Double($0) * 10) })
    #expect(samples[1].speedMps == 10)
  }

  @Test func clipsSortsAndDeduplicatesInputTimestamps() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let raw = RawWorkoutSamples(
      heartRates: [
        TimedQuantity(date: start.addingTimeInterval(3), value: 130),
        TimedQuantity(date: start.addingTimeInterval(-1), value: 90),
        TimedQuantity(date: start.addingTimeInterval(1), value: 120),
        TimedQuantity(date: start.addingTimeInterval(1), value: 121),
        TimedQuantity(date: start.addingTimeInterval(5), value: 150),
      ],
      distances: [], speeds: [], cadences: [], powers: [], locations: [])

    let samples = WorkoutSampleMerger.merge(
      raw: raw, startDate: start, endDate: start.addingTimeInterval(4))

    #expect(
      samples.map(\.timestamp) == [
        start.addingTimeInterval(1), start.addingTimeInterval(3),
      ])
    #expect(samples[0].heartRateBpm == 121)
  }
}

@Suite struct HealthKitWorkoutLoaderTests {
  @Test func convertsIntervalDistancesToCumulativeDistanceAtIntervalEnd() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let result = HealthKitWorkoutLoader.cumulativeDistanceSamples(from: [
      TimedQuantity(date: start.addingTimeInterval(20), value: 7),
      TimedQuantity(date: start.addingTimeInterval(10), value: 5),
      TimedQuantity(date: start.addingTimeInterval(30), value: 8),
    ])

    #expect(result.map(\.value) == [5, 12, 20])
    #expect(
      result.map(\.date) == [
        start.addingTimeInterval(10),
        start.addingTimeInterval(20),
        start.addingTimeInterval(30),
      ])
  }
}
