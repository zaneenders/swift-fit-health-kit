import Foundation
import SwiftFit

public enum WorkoutFITEncodingError: Error, Sendable, Equatable {
  case invalidDate
  case invalidDuration
  case invalidDistance
  case invalidEnergy
  case invalidSample(Date)
}

public enum WorkoutFITEncoder {
  private static let semicirclesPerDegree = 2_147_483_648.0 / 180.0

  public static func encode(bundle: WorkoutExportBundle) throws -> Data {
    Data(try encodeBytes(bundle: bundle))
  }

  private static func encodeBytes(bundle: WorkoutExportBundle) throws -> [UInt8] {
    try validate(bundle: bundle)
    var writer = FITWriter()
    // Record definitions put timestamp first. FIT compressed timestamp records
    // may only omit a trailing timestamp field; compressing this layout shifts
    // every subsequent field and produces an unreadable file.
    writer.useCompressedTimestamps = false

    let startTimestamp = try fitTimestamp(bundle.startDate)
    let endTimestamp = try fitTimestamp(bundle.endDate)
    let elapsedSeconds = bundle.endDate.timeIntervalSince(bundle.startDate)
    let timerSeconds = min(bundle.duration, elapsedSeconds)
    let elapsedMilliseconds = scaledUInt32(elapsedSeconds, scale: 1_000)
    let timerMilliseconds = scaledUInt32(timerSeconds, scale: 1_000)

    let sortedSamples = bundle.samples.sorted { $0.timestamp < $1.timestamp }
    let recordSamples = preparedRecordSamples(
      from: sortedSamples.isEmpty
        ? [
          RecordSample(timestamp: bundle.startDate),
          RecordSample(timestamp: bundle.endDate),
        ]
        : sortedSamples.map(RecordSample.init(sample:)),
      totalDistanceMeters: bundle.totalDistanceMeters
    )

    let heartRates = recordSamples.compactMap(\.heartRateBpm)
    let avgHeartRate = averageHeartRate(from: heartRates)
    let maxHeartRate = heartRates.max()

    let totalDistance =
      bundle.totalDistanceMeters
      ?? recordSamples.compactMap(\.distanceMeters).max()
      ?? 0

    let hasGPS = recordSamples.contains {
      guard let lat = $0.latitude, let lon = $0.longitude else { return false }
      return lat.isFinite && lon.isFinite
    }

    let sport = bundle.sport.fitSportRawValue
    let subSport = bundle.sport.fitSubSportRawValue

    // file_id
    let fileIDLocal = try writer.define(
      globalMessageNumber: FITGlobalMessage.fileID,
      fields: [
        (0, 1, .enumType),
        (1, 2, .uint16),
        (2, 2, .uint16),
        (3, 4, .uint32),
        (4, 4, .uint32),
      ])
    try writer.write(
      localType: fileIDLocal,
      values: [
        .enumType(FITFileType.activity.rawValue),
        .uint16(FITManufacturer.development.rawValue),
        .uint16(0),
        .uint32(1),
        .uint32(startTimestamp),
      ])

    // timer start
    let eventLocal = try writer.define(
      globalMessageNumber: FITGlobalMessage.event,
      fields: [
        (253, 4, .uint32),
        (0, 1, .enumType),
        (1, 1, .enumType),
      ])
    try writer.write(
      localType: eventLocal,
      values: [
        .uint32(startTimestamp),
        .enumType(FITEvent.timer.rawValue),
        .enumType(FITEventType.start.rawValue),
      ])

    let recordLocal: UInt8
    if hasGPS {
      recordLocal = try writer.define(
        globalMessageNumber: FITGlobalMessage.record,
        fields: [
          (FITRecordField.timestamp, 4, .uint32),
          (FITRecordField.positionLat, 4, .sint32),
          (FITRecordField.positionLong, 4, .sint32),
          (FITRecordField.altitude, 2, .uint16),
          (FITRecordField.distance, 4, .uint32),
          (FITRecordField.speed, 2, .uint16),
          (FITRecordField.heartRate, 1, .uint8),
          (4, 1, .uint8),  // cadence
          (7, 2, .uint16),  // power
        ])
    } else {
      recordLocal = try writer.define(
        globalMessageNumber: FITGlobalMessage.record,
        fields: [
          (FITRecordField.timestamp, 4, .uint32),
          (FITRecordField.distance, 4, .uint32),
          (FITRecordField.speed, 2, .uint16),
          (FITRecordField.heartRate, 1, .uint8),
          (4, 1, .uint8),  // cadence
          (7, 2, .uint16),  // power
        ])
    }

    for sample in recordSamples {
      let timestamp = try fitTimestamp(sample.timestamp)

      let distanceValue: Value
      if let meters = sample.distanceMeters {
        distanceValue = .uint32(scaledUInt32(meters, scale: 100))
      } else {
        distanceValue = .invalid
      }

      let speedValue: Value
      if let speed = sample.speedMps {
        speedValue = .uint16(scaledUInt16(speed, scale: 1_000))
      } else {
        speedValue = .invalid
      }

      let heartRateValue: Value
      if let hr = sample.heartRateBpm {
        heartRateValue = .uint8(hr)
      } else {
        heartRateValue = .invalid
      }

      let cadenceValue = sample.cadenceRpm.map(Value.uint8) ?? .invalid
      let powerValue = sample.powerWatts.map(Value.uint16) ?? .invalid

      if hasGPS {
        let latValue: Value
        let lonValue: Value
        if let lat = sample.latitude, let lon = sample.longitude, lat.isFinite, lon.isFinite {
          latValue = .sint32(degreesToSemicircles(lat))
          lonValue = .sint32(degreesToSemicircles(lon))
        } else {
          latValue = .invalid
          lonValue = .invalid
        }

        let altitudeValue: Value
        if let altitude = sample.altitudeMeters {
          altitudeValue = altitudeFieldValue(meters: altitude)
        } else {
          altitudeValue = .invalid
        }

        try writer.write(
          localType: recordLocal,
          values: [
            .uint32(timestamp),
            latValue,
            lonValue,
            altitudeValue,
            distanceValue,
            speedValue,
            heartRateValue,
            cadenceValue,
            powerValue,
          ])
      } else {
        try writer.write(
          localType: recordLocal,
          values: [
            .uint32(timestamp),
            distanceValue,
            speedValue,
            heartRateValue,
            cadenceValue,
            powerValue,
          ])
      }
    }

    // timer stop
    try writer.write(
      localType: eventLocal,
      values: [
        .uint32(endTimestamp),
        .enumType(FITEvent.timer.rawValue),
        .enumType(FITEventType.stopAll.rawValue),
      ])

    // lap
    let lapLocal = try writer.define(
      globalMessageNumber: FITGlobalMessage.lap,
      fields: [
        (254, 2, .uint16),
        (253, 4, .uint32),
        (FITSessionField.startTime, 4, .uint32),
        (FITSessionField.totalElapsedTime, 4, .uint32),
        (FITSessionField.totalTimerTime, 4, .uint32),
        (FITSessionField.totalDistance, 4, .uint32),
      ])
    try writer.write(
      localType: lapLocal,
      values: [
        .uint16(0),
        .uint32(endTimestamp),
        .uint32(startTimestamp),
        .uint32(elapsedMilliseconds),
        .uint32(timerMilliseconds),
        .uint32(scaledUInt32(totalDistance, scale: 100)),
      ])

    // session
    let sessionLocal = try writer.define(
      globalMessageNumber: FITGlobalMessage.session,
      fields: [
        (254, 2, .uint16),
        (FITSessionField.timestamp, 4, .uint32),
        (FITSessionField.startTime, 4, .uint32),
        (FITSessionField.sport, 1, .enumType),
        (FITSessionField.subSport, 1, .enumType),
        (FITSessionField.totalElapsedTime, 4, .uint32),
        (FITSessionField.totalTimerTime, 4, .uint32),
        (FITSessionField.totalDistance, 4, .uint32),
        (11, 2, .uint16),
        (14, 1, .uint8),
        (15, 1, .uint8),
        (25, 2, .uint16),
        (26, 2, .uint16),
      ])

    var sessionValues: [Value] = [
      .uint16(0),
      .uint32(endTimestamp),
      .uint32(startTimestamp),
      .enumType(sport),
      .enumType(subSport),
      .uint32(elapsedMilliseconds),
      .uint32(timerMilliseconds),
      .uint32(scaledUInt32(totalDistance, scale: 100)),
    ]

    if let kcal = bundle.totalEnergyKcal {
      sessionValues.append(.uint16(scaledUInt16(kcal, scale: 1)))
    } else {
      sessionValues.append(.invalid)
    }

    if let avgHeartRate {
      sessionValues.append(.uint8(avgHeartRate))
    } else {
      sessionValues.append(.invalid)
    }

    if let maxHeartRate {
      sessionValues.append(.uint8(maxHeartRate))
    } else {
      sessionValues.append(.invalid)
    }

    sessionValues.append(.uint16(0))
    sessionValues.append(.uint16(1))

    try writer.write(localType: sessionLocal, values: sessionValues)

    // activity
    let activityLocal = try writer.define(
      globalMessageNumber: FITGlobalMessage.activity,
      fields: [
        (253, 4, .uint32),
        (0, 4, .uint32),
        (5, 2, .uint16),
      ])
    try writer.write(
      localType: activityLocal,
      values: [
        .uint32(endTimestamp),
        .uint32(timerMilliseconds),
        .uint16(1),
      ])

    return writer.finish()
  }

  private struct RecordSample {
    let timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var altitudeMeters: Double?
    var heartRateBpm: UInt8?
    var distanceMeters: Double?
    var speedMps: Double?
    var cadenceRpm: UInt8?
    var powerWatts: UInt16?

    init(timestamp: Date) {
      self.timestamp = timestamp
    }

    init(sample: WorkoutSample) {
      timestamp = sample.timestamp
      latitude = sample.latitude
      longitude = sample.longitude
      altitudeMeters = sample.altitudeMeters
      heartRateBpm = sample.heartRateBpm
      distanceMeters = sample.distanceMeters
      speedMps = sample.speedMps
      cadenceRpm = sample.cadenceRpm
      powerWatts = sample.powerWatts
    }
  }

  private static func preparedRecordSamples(
    from samples: [RecordSample],
    totalDistanceMeters: Double?
  ) -> [RecordSample] {
    guard !samples.isEmpty else { return samples }

    var result = samples
    let hasGPS = result.contains {
      guard let lat = $0.latitude, let lon = $0.longitude else { return false }
      return lat.isFinite && lon.isFinite
    }

    if hasGPS {
      var cumulative: [Double] = []
      cumulative.reserveCapacity(result.count)
      var total = 0.0
      var previousLatitude: Double?
      var previousLongitude: Double?

      for sample in result {
        if let lat = sample.latitude,
          let lon = sample.longitude,
          let prevLat = previousLatitude,
          let prevLon = previousLongitude
        {
          total += haversineMeters(
            lat1: prevLat,
            lon1: prevLon,
            lat2: lat,
            lon2: lon
          )
        }
        cumulative.append(total)
        previousLatitude = sample.latitude
        previousLongitude = sample.longitude
      }

      let targetTotal = totalDistanceMeters ?? cumulative.last ?? 0
      let computedTotal = cumulative.last ?? 0
      let scale =
        computedTotal > 0 && targetTotal > 0 ? targetTotal / computedTotal : 1.0

      for index in result.indices {
        let scaledDistance = cumulative[index] * scale
        let existing = result[index].distanceMeters ?? 0
        if existing < scaledDistance * 0.9 {
          result[index].distanceMeters = scaledDistance
        }
      }
      return result
    }

    guard let totalDistanceMeters, totalDistanceMeters > 0 else { return result }

    let recordMax = result.compactMap(\.distanceMeters).max() ?? 0
    guard recordMax < totalDistanceMeters * 0.9 else { return result }

    let count = result.count
    guard count > 1 else {
      if result[0].distanceMeters == nil {
        result[0].distanceMeters = totalDistanceMeters
      }
      return result
    }

    for index in result.indices {
      result[index].distanceMeters =
        totalDistanceMeters * Double(index) / Double(count - 1)
    }
    return result
  }

  private static func fitTimestamp(_ date: Date) throws -> UInt32 {
    let seconds = date.timeIntervalSince1970 - Double(fitEpochOffset)
    guard seconds.isFinite, seconds >= 0, seconds <= Double(UInt32.max) else {
      throw WorkoutFITEncodingError.invalidDate
    }
    return UInt32(seconds.rounded(.down))
  }

  private static func degreesToSemicircles(_ degrees: Double) -> Int32 {
    // Longitude 180 degrees is represented by the Int32 bit pattern 0x80000000.
    if degrees == 180 { return Int32.min }
    return Int32((degrees * semicirclesPerDegree).rounded())
  }

  private static func altitudeFieldValue(meters: Double) -> Value {
    .uint16(scaledUInt16(meters + 500, scale: 5))
  }

  private static func scaledUInt16(_ value: Double, scale: Double) -> UInt16 {
    guard value > 0 else { return 0 }
    guard value.isFinite, scale.isFinite, value <= Double(UInt16.max) / scale else {
      return UInt16.max
    }
    return UInt16((value * scale).rounded())
  }

  private static func scaledUInt32(_ value: Double, scale: Double) -> UInt32 {
    guard value > 0 else { return 0 }
    guard value.isFinite, scale.isFinite, value <= Double(UInt32.max) / scale else {
      return UInt32.max
    }
    return UInt32((value * scale).rounded())
  }

  private static func validate(bundle: WorkoutExportBundle) throws {
    let start = bundle.startDate.timeIntervalSince1970
    let end = bundle.endDate.timeIntervalSince1970
    let earliestFITDate = Double(fitEpochOffset)
    let latestFITDate = earliestFITDate + Double(UInt32.max)
    guard start.isFinite, end.isFinite, start >= earliestFITDate, end >= start, end <= latestFITDate else {
      throw WorkoutFITEncodingError.invalidDate
    }
    guard bundle.duration.isFinite, bundle.duration >= 0 else {
      throw WorkoutFITEncodingError.invalidDuration
    }
    if let distance = bundle.totalDistanceMeters,
      !distance.isFinite || distance < 0
    {
      throw WorkoutFITEncodingError.invalidDistance
    }
    if let energy = bundle.totalEnergyKcal,
      !energy.isFinite || energy < 0
    {
      throw WorkoutFITEncodingError.invalidEnergy
    }

    for sample in bundle.samples {
      let timestamp = sample.timestamp.timeIntervalSince1970
      let quantities = [sample.distanceMeters, sample.speedMps, sample.altitudeMeters]
      let coordinatesAreValid =
        sample.latitude.map { $0.isFinite && (-90...90).contains($0) } ?? true
        && sample.longitude.map { $0.isFinite && (-180...180).contains($0) } ?? true
      let hasCoordinatePair = (sample.latitude == nil) == (sample.longitude == nil)
      guard timestamp.isFinite,
        timestamp >= earliestFITDate,
        timestamp <= latestFITDate,
        quantities.allSatisfy({ $0.map { $0.isFinite } ?? true }),
        sample.distanceMeters.map({ $0 >= 0 }) ?? true,
        sample.speedMps.map({ $0 >= 0 }) ?? true,
        coordinatesAreValid,
        hasCoordinatePair
      else {
        throw WorkoutFITEncodingError.invalidSample(sample.timestamp)
      }
    }
  }

  private static func haversineMeters(
    lat1: Double,
    lon1: Double,
    lat2: Double,
    lon2: Double
  ) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180.0
    let dLon = (lon2 - lon1) * .pi / 180.0
    let a =
      sin(dLat / 2) * sin(dLat / 2)
      + cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) * sin(dLon / 2) * sin(dLon / 2)
    // Floating-point rounding can put a microscopically outside 0...1.
    let clampedA = min(1, max(0, a))
    let c = 2 * atan2(sqrt(clampedA), sqrt(1 - clampedA))
    return earthRadius * c
  }

  private static func averageHeartRate(from values: [UInt8]) -> UInt8? {
    guard !values.isEmpty else { return nil }
    let total = values.reduce(UInt(0)) { $0 + UInt($1) }
    return UInt8(total / UInt(values.count))
  }
}

extension WorkoutSport {
  fileprivate var fitSportRawValue: UInt8 {
    switch self {
    case .running: 1
    case .cycling: 2
    case .swimming: 5
    case .walking: 11
    case .crossCountrySkiing: 12
    case .downhillSkiing: 13
    case .snowboarding: 14
    case .rowing: 15
    case .hiking: 17
    case .elliptical, .stairClimbing: 4
    case .crossTraining, .strengthTraining, .highIntensityIntervalTraining, .yoga, .pilates: 10
    case .dance: 4
    // The dependency's FIT profile currently has no typed mappings for these.
    // Generic is preferable to emitting an unverified raw sport value.
    case .wheelchair, .other: 0
    }
  }

  fileprivate var fitSubSportRawValue: UInt8 {
    switch self {
    case .running(let indoor): indoor ? 1 : 0
    case .walking(let indoor): indoor ? 27 : 0
    case .cycling(let indoor): indoor ? 6 : 0
    case .swimming(let indoor): indoor ? 17 : 18
    case .rowing(let indoor): indoor ? 14 : 0
    case .elliptical: 15
    case .stairClimbing: 16
    case .strengthTraining: 20
    case .highIntensityIntervalTraining: 65
    case .yoga: 43
    case .pilates: 44
    default: 0
    }
  }
}
