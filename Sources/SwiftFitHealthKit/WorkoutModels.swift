import Foundation
import HealthKit

public struct TimedQuantity: Sendable, Hashable {
  public let date: Date
  public let value: Double

  public init(date: Date, value: Double) {
    self.date = date
    self.value = value
  }
}

public struct TimedLocation: Sendable, Hashable {
  public let date: Date
  public let latitude: Double
  public let longitude: Double
  public let altitudeMeters: Double?

  public init(
    date: Date,
    latitude: Double,
    longitude: Double,
    altitudeMeters: Double?
  ) {
    self.date = date
    self.latitude = latitude
    self.longitude = longitude
    self.altitudeMeters = altitudeMeters
  }
}

public struct RawWorkoutSamples: Sendable {
  public let heartRates: [TimedQuantity]
  public let distances: [TimedQuantity]
  public let speeds: [TimedQuantity]
  public let cadences: [TimedQuantity]
  public let powers: [TimedQuantity]
  public let locations: [TimedLocation]

  public init(
    heartRates: [TimedQuantity],
    distances: [TimedQuantity],
    speeds: [TimedQuantity],
    cadences: [TimedQuantity],
    powers: [TimedQuantity],
    locations: [TimedLocation]
  ) {
    self.heartRates = heartRates
    self.distances = distances
    self.speeds = speeds
    self.cadences = cadences
    self.powers = powers
    self.locations = locations
  }
}

public struct WorkoutSample: Sendable, Hashable {
  public let timestamp: Date
  public let heartRateBpm: UInt8?
  public let distanceMeters: Double?
  public let speedMps: Double?
  public let cadenceRpm: UInt8?
  public let powerWatts: UInt16?
  public let latitude: Double?
  public let longitude: Double?
  public let altitudeMeters: Double?

  public init(
    timestamp: Date,
    heartRateBpm: UInt8? = nil,
    distanceMeters: Double? = nil,
    speedMps: Double? = nil,
    cadenceRpm: UInt8? = nil,
    powerWatts: UInt16? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    altitudeMeters: Double? = nil
  ) {
    self.timestamp = timestamp
    self.heartRateBpm = heartRateBpm
    self.distanceMeters = distanceMeters
    self.speedMps = speedMps
    self.cadenceRpm = cadenceRpm
    self.powerWatts = powerWatts
    self.latitude = latitude
    self.longitude = longitude
    self.altitudeMeters = altitudeMeters
  }
}

public enum WorkoutSport: Sendable, Hashable {
  case running(indoor: Bool)
  case walking(indoor: Bool)
  case cycling(indoor: Bool)

  public init(workout: HKWorkout) {
    let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
    switch workout.workoutActivityType {
    case .cycling:
      self = .cycling(indoor: indoor)
    case .walking:
      self = .walking(indoor: indoor)
    case .running:
      self = .running(indoor: indoor)
    default:
      self = .running(indoor: indoor)
    }
  }

  public var label: String {
    switch self {
    case .running(let indoor): indoor ? "Indoor Run" : "Run"
    case .walking(let indoor): indoor ? "Indoor Walk" : "Walk"
    case .cycling(let indoor): indoor ? "Indoor Ride" : "Ride"
    }
  }

  public var filenameComponent: String {
    switch self {
    case .running(let indoor): indoor ? "indoor-run" : "run"
    case .walking(let indoor): indoor ? "indoor-walk" : "walk"
    case .cycling(let indoor): indoor ? "indoor-ride" : "ride"
    }
  }
}

public struct WorkoutExportBundle: Sendable {
  public let startDate: Date
  public let endDate: Date
  public let duration: TimeInterval
  public let totalDistanceMeters: Double?
  public let totalEnergyKcal: Double?
  public let sport: WorkoutSport
  public let samples: [WorkoutSample]

  public init(
    startDate: Date,
    endDate: Date,
    duration: TimeInterval,
    totalDistanceMeters: Double?,
    totalEnergyKcal: Double?,
    sport: WorkoutSport,
    samples: [WorkoutSample]
  ) {
    self.startDate = startDate
    self.endDate = endDate
    self.duration = duration
    self.totalDistanceMeters = totalDistanceMeters
    self.totalEnergyKcal = totalEnergyKcal
    self.sport = sport
    self.samples = samples
  }
}
