import Foundation

/// Resamples HealthKit's independently timestamped series into FIT record samples.
///
/// Policy:
/// - Route timestamps are the record timeline when a route is available. This preserves
///   recorded coordinates without inventing locations.
/// - Otherwise, the timeline is the sorted union of every quantity-series timestamp.
/// - Heart rate, speed, cadence, and power use the latest observation at or before a
///   record timestamp. Values are carried forward only for a bounded, adaptive interval.
/// - Cumulative distance is linearly interpolated between observations. It is never
///   extrapolated past the final observation or allowed to decrease.
/// - Input and output timestamps are clipped to the workout interval.
public enum WorkoutSampleMerger {
  public static func merge(
    raw: RawWorkoutSamples,
    startDate: Date,
    endDate: Date
  ) -> [WorkoutSample] {
    guard endDate >= startDate else { return [] }

    let heartRates = normalized(raw.heartRates, from: startDate, through: endDate)
    let distances = normalizedCumulative(raw.distances, from: startDate, through: endDate)
    let speeds = normalized(raw.speeds, from: startDate, through: endDate)
    let cadences = normalized(raw.cadences, from: startDate, through: endDate)
    let powers = normalized(raw.powers, from: startDate, through: endDate)
    let locations = normalized(raw.locations, from: startDate, through: endDate)

    let timeline: [Date]
    if locations.isEmpty {
      timeline = quantityTimeline(
        series: [heartRates, distances, speeds, cadences, powers],
        startDate: startDate,
        endDate: endDate
      )
    } else {
      timeline = locations.map(\.date)
    }

    let heartRateTolerance = carryForwardTolerance(for: heartRates)
    let speedTolerance = carryForwardTolerance(for: speeds)
    let cadenceTolerance = carryForwardTolerance(for: cadences)
    let powerTolerance = carryForwardTolerance(for: powers)

    var samples: [WorkoutSample] = []
    samples.reserveCapacity(timeline.count)

    var previousDistance: Double?
    var previousDistanceDate: Date?

    for (index, date) in timeline.enumerated() {
      let distanceMeters = interpolatedDistance(
        in: distances,
        at: date,
        workoutStart: startDate
      )
      let nativeSpeed = latestValue(
        in: speeds,
        at: date,
        tolerance: speedTolerance
      )
      let derivedSpeed: Double?
      if nativeSpeed == nil,
        let distanceMeters,
        let previousDistance,
        let previousDistanceDate,
        date > previousDistanceDate
      {
        let delta = distanceMeters - previousDistance
        let seconds = date.timeIntervalSince(previousDistanceDate)
        derivedSpeed = delta >= 0 ? delta / seconds : nil
      } else {
        derivedSpeed = nil
      }

      let location = locations.isEmpty ? nil : locations[index]
      samples.append(
        WorkoutSample(
          timestamp: date,
          heartRateBpm: latestValue(
            in: heartRates,
            at: date,
            tolerance: heartRateTolerance
          ).flatMap(uint8Measurement),
          distanceMeters: distanceMeters,
          speedMps: nativeSpeed ?? derivedSpeed,
          cadenceRpm: latestValue(
            in: cadences,
            at: date,
            tolerance: cadenceTolerance
          ).flatMap(uint8Measurement),
          powerWatts: latestValue(
            in: powers,
            at: date,
            tolerance: powerTolerance
          ).flatMap(uint16Measurement),
          latitude: location?.latitude,
          longitude: location?.longitude,
          altitudeMeters: location?.altitudeMeters
        ))

      if let distanceMeters {
        previousDistance = distanceMeters
        previousDistanceDate = date
      }
    }

    return samples
  }

  private static func quantityTimeline(
    series: [[TimedQuantity]],
    startDate: Date,
    endDate: Date
  ) -> [Date] {
    let dates = Set(series.flatMap { $0.map(\.date) })
    if dates.isEmpty {
      return startDate == endDate ? [startDate] : [startDate, endDate]
    }
    return dates.sorted()
  }

  /// Limits stale instantaneous measurements while adapting to sensors that sample
  /// less frequently. A singleton is valid for two seconds; regularly sampled data
  /// is valid for 1.5 sample intervals, bounded to 2...10 seconds.
  private static func carryForwardTolerance(for series: [TimedQuantity]) -> TimeInterval {
    let intervals = zip(series, series.dropFirst())
      .map { $1.date.timeIntervalSince($0.date) }
      .filter { $0 > 0 && $0.isFinite }
      .sorted()
    guard !intervals.isEmpty else { return 2 }
    // Use the lower median so a single long dropout does not make stale values
    // appear valid throughout that same dropout.
    let median = intervals[(intervals.count - 1) / 2]
    return min(10, max(2, median * 1.5))
  }

  /// Uses only an observation at or before the record timestamp, so a future sensor
  /// reading is never copied backward into an earlier FIT record.
  private static func latestValue(
    in series: [TimedQuantity],
    at date: Date,
    tolerance: TimeInterval
  ) -> Double? {
    guard let sample = series.last(where: { $0.date <= date }) else { return nil }
    guard date.timeIntervalSince(sample.date) <= tolerance else { return nil }
    return sample.value
  }

  private static func interpolatedDistance(
    in series: [TimedQuantity],
    at date: Date,
    workoutStart: Date
  ) -> Double? {
    guard !series.isEmpty else { return nil }

    var points = series
    if let first = points.first, first.date > workoutStart {
      points.insert(TimedQuantity(date: workoutStart, value: 0), at: 0)
    }

    if let exact = points.last(where: { $0.date == date }) {
      return exact.value
    }
    guard let upperIndex = points.firstIndex(where: { $0.date > date }), upperIndex > 0 else {
      // Do not guess continued movement after the final distance observation.
      return nil
    }

    let lower = points[upperIndex - 1]
    let upper = points[upperIndex]
    let interval = upper.date.timeIntervalSince(lower.date)
    guard interval > 0 else { return upper.value }
    let fraction = date.timeIntervalSince(lower.date) / interval
    return lower.value + (upper.value - lower.value) * fraction
  }

  private static func normalized(
    _ series: [TimedQuantity],
    from startDate: Date,
    through endDate: Date
  ) -> [TimedQuantity] {
    var byDate: [Date: TimedQuantity] = [:]
    for sample in series
    where sample.date >= startDate && sample.date <= endDate && sample.value.isFinite {
      byDate[sample.date] = sample
    }
    return byDate.values.sorted { $0.date < $1.date }
  }

  private static func normalizedCumulative(
    _ series: [TimedQuantity],
    from startDate: Date,
    through endDate: Date
  ) -> [TimedQuantity] {
    let sorted = normalized(series, from: startDate, through: endDate)
    var result: [TimedQuantity] = []
    result.reserveCapacity(sorted.count)
    var previous = -Double.infinity
    for sample in sorted where sample.value >= 0 && sample.value >= previous {
      result.append(sample)
      previous = sample.value
    }
    return result
  }

  private static func normalized(
    _ locations: [TimedLocation],
    from startDate: Date,
    through endDate: Date
  ) -> [TimedLocation] {
    var byDate: [Date: TimedLocation] = [:]
    for location in locations
    where location.date >= startDate
      && location.date <= endDate
      && location.latitude.isFinite
      && location.longitude.isFinite
      && location.altitudeMeters.map({ $0.isFinite }) ?? true
    {
      byDate[location.date] = location
    }
    return byDate.values.sorted { $0.date < $1.date }
  }

  private static func uint8Measurement(_ value: Double) -> UInt8? {
    guard value.isFinite else { return nil }
    return UInt8(min(Double(UInt8.max), max(0, value)).rounded())
  }

  private static func uint16Measurement(_ value: Double) -> UInt16? {
    guard value.isFinite else { return nil }
    return UInt16(min(Double(UInt16.max), max(0, value)).rounded())
  }
}
