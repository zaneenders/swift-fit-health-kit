import Foundation
import Testing

@testable import SwiftFitHealthKit

@Suite struct WorkoutSampleMergerTests {
  @Test func mergesHealthQuantitiesOntoRouteTimeline() throws {
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
    #expect(samples[1].heartRateBpm == 140)
    #expect(samples[1].speedMps == 5)
    #expect(samples[1].cadenceRpm == 82)
    #expect(samples[1].powerWatts == 245)
  }

  @Test func usesHeartRateTimelineWithoutRoute() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let raw = RawWorkoutSamples(
      heartRates: [TimedQuantity(date: start, value: 121)],
      distances: [], speeds: [], cadences: [], powers: [], locations: [])

    let samples = WorkoutSampleMerger.merge(raw: raw, startDate: start, endDate: start)
    #expect(samples.count == 1)
    #expect(samples[0].heartRateBpm == 121)
    #expect(samples[0].latitude == nil)
  }
}
