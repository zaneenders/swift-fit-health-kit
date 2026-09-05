import Foundation

public enum WorkoutSampleMerger {
  public static func merge(
    raw: RawWorkoutSamples,
    startDate: Date,
    endDate: Date
  ) -> [WorkoutSample] {
    if !raw.locations.isEmpty {
      return mergeRouteSamples(raw: raw)
    }

    let timeline = timelineDates(
      heartRates: raw.heartRates,
      distances: raw.distances,
      startDate: startDate,
      endDate: endDate
    )

    var samples: [WorkoutSample] = []
    samples.reserveCapacity(timeline.count)

    var previousDistance: Double?
    var previousDate: Date?

    for date in timeline {
      let heartRateBpm = nearestValue(in: raw.heartRates, around: date).map {
        UInt8(max(0, min(255, $0.rounded())))
      }
      let distanceMeters = nearestValue(in: raw.distances, around: date)
      let speedFromSeries = nearestValue(in: raw.speeds, around: date)
      let speedMps: Double?
      if let speedFromSeries {
        speedMps = speedFromSeries
      } else if let distanceMeters, let previousDistance, let previousDate, date > previousDate {
        let delta = distanceMeters - previousDistance
        let seconds = date.timeIntervalSince(previousDate)
        speedMps = seconds > 0 && delta >= 0 ? delta / seconds : nil
      } else {
        speedMps = nil
      }
      let cadenceRpm = nearestValue(in: raw.cadences, around: date).map {
        UInt8(max(0, min(255, $0.rounded())))
      }
      let powerWatts = nearestValue(in: raw.powers, around: date).map {
        UInt16(max(0, min(65_535, $0.rounded())))
      }

      let sample = WorkoutSample(
        timestamp: date,
        heartRateBpm: heartRateBpm,
        distanceMeters: distanceMeters,
        speedMps: speedMps,
        cadenceRpm: cadenceRpm,
        powerWatts: powerWatts,
        latitude: nil,
        longitude: nil,
        altitudeMeters: nil
      )

      if let distance = sample.distanceMeters {
        previousDistance = distance
        previousDate = date
      }
      samples.append(sample)
    }

    return samples
  }

  private static func mergeRouteSamples(raw: RawWorkoutSamples) -> [WorkoutSample] {
    var samples: [WorkoutSample] = []
    samples.reserveCapacity(raw.locations.count)

    var previousDistance: Double?
    var previousDate: Date?

    for location in raw.locations {
      let date = location.date
      let heartRateBpm = nearestValue(in: raw.heartRates, around: date).map {
        UInt8(max(0, min(255, $0.rounded())))
      }
      let distanceMeters = nearestValue(in: raw.distances, around: date)
      let speedFromSeries = nearestValue(in: raw.speeds, around: date)
      let speedMps: Double?
      if let speedFromSeries {
        speedMps = speedFromSeries
      } else if let distanceMeters, let previousDistance, let previousDate, date > previousDate {
        let delta = distanceMeters - previousDistance
        let seconds = date.timeIntervalSince(previousDate)
        speedMps = seconds > 0 && delta >= 0 ? delta / seconds : nil
      } else {
        speedMps = nil
      }
      let cadenceRpm = nearestValue(in: raw.cadences, around: date).map {
        UInt8(max(0, min(255, $0.rounded())))
      }
      let powerWatts = nearestValue(in: raw.powers, around: date).map {
        UInt16(max(0, min(65_535, $0.rounded())))
      }

      samples.append(
        WorkoutSample(
          timestamp: date,
          heartRateBpm: heartRateBpm,
          distanceMeters: distanceMeters,
          speedMps: speedMps,
          cadenceRpm: cadenceRpm,
          powerWatts: powerWatts,
          latitude: location.latitude,
          longitude: location.longitude,
          altitudeMeters: location.altitudeMeters
        ))

      if let distance = distanceMeters {
        previousDistance = distance
        previousDate = date
      }
    }

    return samples
  }

  private static func timelineDates(
    heartRates: [TimedQuantity],
    distances: [TimedQuantity],
    startDate: Date,
    endDate: Date
  ) -> [Date] {
    if !heartRates.isEmpty {
      return heartRates.map(\.date)
    }
    if !distances.isEmpty {
      return distances.map(\.date)
    }
    return [startDate, endDate]
  }

  private static func nearestValue(in series: [TimedQuantity], around date: Date) -> Double? {
    guard !series.isEmpty else { return nil }
    var best = series[0]
    var bestDelta = abs(best.date.timeIntervalSince(date))
    for item in series.dropFirst() {
      let delta = abs(item.date.timeIntervalSince(date))
      if delta < bestDelta {
        best = item
        bestDelta = delta
      }
    }
    return best.value
  }
}
