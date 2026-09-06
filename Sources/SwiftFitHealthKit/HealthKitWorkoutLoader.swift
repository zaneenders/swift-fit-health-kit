import CoreLocation
import Foundation
import HealthKit
import Synchronization

private final class RouteLocationCollector: Sendable {
  private struct State: Sendable {
    var locations: [TimedLocation] = []
    var isFinished = false
  }

  private let state = Mutex(State())

  nonisolated func append(contentsOf newLocations: [TimedLocation]) {
    state.withLock { state in
      guard !state.isFinished else { return }
      state.locations.append(contentsOf: newLocations)
    }
  }

  nonisolated func finish() -> [TimedLocation]? {
    state.withLock { state in
      guard !state.isFinished else { return nil }
      state.isFinished = true
      return state.locations
    }
  }
}

public enum HealthKitWorkoutLoader {
  public static func loadRawSamples(for workout: HKWorkout, store: HKHealthStore) async throws -> RawWorkoutSamples {
    let workoutPredicate = HKQuery.predicateForObjects(from: workout)
    let heartRates = try await quantitySamples(
      identifier: .heartRate,
      unit: HKUnit.count().unitDivided(by: .minute()),
      predicate: workoutPredicate,
      store: store
    )
    let distances = try await distanceSamples(for: workout, predicate: workoutPredicate, store: store)
    let speeds = try await speedSamples(for: workout, predicate: workoutPredicate, store: store)
    let cadences = try await quantitySamples(
      identifier: .cyclingCadence,
      unit: HKUnit.count().unitDivided(by: .minute()),
      predicate: workoutPredicate,
      store: store
    )
    let powers = try await quantitySamples(
      identifier: .cyclingPower,
      unit: .watt(),
      predicate: workoutPredicate,
      store: store
    )
    let locations = try await routeLocations(for: workout, store: store)

    return RawWorkoutSamples(
      heartRates: heartRates,
      distances: distances,
      speeds: speeds,
      cadences: cadences,
      powers: powers,
      locations: locations
    )
  }

  public static func exportBundle(
    for workout: HKWorkout,
    store: HKHealthStore
  ) async throws -> WorkoutExportBundle {
    let raw = try await loadRawSamples(for: workout, store: store)
    let sport = WorkoutSport(workout: workout)
    let totalDistance = workout.totalDistance?.doubleValue(for: .meter())
    let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    let totalEnergy = workout.statistics(for: energyType)?
      .sumQuantity()?
      .doubleValue(for: .kilocalorie())
    let samples = WorkoutSampleMerger.merge(
      raw: raw,
      startDate: workout.startDate,
      endDate: workout.endDate
    )
    return WorkoutExportBundle(
      startDate: workout.startDate,
      endDate: workout.endDate,
      duration: workout.duration,
      totalDistanceMeters: totalDistance,
      totalEnergyKcal: totalEnergy,
      sport: sport,
      samples: samples
    )
  }

  private static func distanceSamples(
    for workout: HKWorkout,
    predicate: NSPredicate,
    store: HKHealthStore
  ) async throws -> [TimedQuantity] {
    let identifier: HKQuantityTypeIdentifier =
      workout.workoutActivityType == .cycling ? .distanceCycling : .distanceWalkingRunning
    return try await quantitySamples(
      identifier: identifier,
      unit: .meter(),
      predicate: predicate,
      store: store
    )
  }

  private static func speedSamples(
    for workout: HKWorkout,
    predicate: NSPredicate,
    store: HKHealthStore
  ) async throws -> [TimedQuantity] {
    let identifier: HKQuantityTypeIdentifier =
      workout.workoutActivityType == .cycling ? .cyclingSpeed : .runningSpeed
    return try await quantitySamples(
      identifier: identifier,
      unit: HKUnit.meter().unitDivided(by: .second()),
      predicate: predicate,
      store: store
    )
  }

  private static func quantitySamples(
    identifier: HKQuantityTypeIdentifier,
    unit: HKUnit,
    predicate: NSPredicate,
    store: HKHealthStore
  ) async throws -> [TimedQuantity] {
    let type = HKQuantityType.quantityType(forIdentifier: identifier)!
    let descriptor = HKSampleQueryDescriptor(
      predicates: [.quantitySample(type: type, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
    )
    let samples = try await descriptor.result(for: store)
    return samples.map { sample in
      TimedQuantity(
        date: sample.startDate,
        value: sample.quantity.doubleValue(for: unit)
      )
    }
  }

  private static func routeLocations(
    for workout: HKWorkout,
    store: HKHealthStore
  ) async throws -> [TimedLocation] {
    let routes = try await workoutRoutes(for: workout, store: store)
    guard !routes.isEmpty else { return [] }

    var allLocations: [TimedLocation] = []
    for route in routes {
      let routeLocations = try await timedLocations(for: route, store: store)
      allLocations.append(contentsOf: routeLocations)
    }

    return allLocations.sorted { $0.date < $1.date }
  }

  private static func workoutRoutes(
    for workout: HKWorkout,
    store: HKHealthStore
  ) async throws -> [HKWorkoutRoute] {
    let routeType = HKSeriesType.workoutRoute()
    let predicate = HKQuery.predicateForObjects(from: workout)
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: routeType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
      ) { _, samples, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
      }
      store.execute(query)
    }
  }

  private static func timedLocations(
    for route: HKWorkoutRoute,
    store: HKHealthStore
  ) async throws -> [TimedLocation] {
    try await withCheckedThrowingContinuation { continuation in
      let collector = RouteLocationCollector()
      let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
        if let error {
          if collector.finish() != nil {
            continuation.resume(throwing: error)
          }
          return
        }
        if let locations {
          collector.append(contentsOf: locations.map(Self.timedLocation(from:)))
        }
        if done, let collected = collector.finish() {
          continuation.resume(returning: collected)
        }
      }
      store.execute(query)
    }
  }

  nonisolated private static func timedLocation(from location: CLLocation) -> TimedLocation {
    let altitudeMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
    return TimedLocation(
      date: location.timestamp,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      altitudeMeters: altitudeMeters
    )
  }
}
