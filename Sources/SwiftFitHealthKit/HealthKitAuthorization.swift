import HealthKit

public enum HealthKitAuthorizationState: Sendable, Equatable {
  case notDetermined
  /// The authorization sheet has been shown. HealthKit does not report whether read access was granted.
  case prompted
  case unavailable
}

public enum HealthKitAuthorization {
  private static let readTypes: Set<HKObjectType> = {
    var types = Set<HKObjectType>()
    types.insert(HKObjectType.workoutType())
    types.insert(HKSeriesType.workoutRoute())
    let quantityIDs: [HKQuantityTypeIdentifier] = [
      .heartRate,
      .distanceWalkingRunning,
      .distanceCycling,
      .distanceSwimming,
      .distanceWheelchair,
      .runningSpeed,
      .cyclingSpeed,
      .cyclingCadence,
      .cyclingPower,
      .activeEnergyBurned,
    ]
    for identifier in quantityIDs {
      guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
      types.insert(type)
    }
    return types
  }()

  public static func authorizationState() async -> HealthKitAuthorizationState {
    guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
    let store = HKHealthStore()
    do {
      let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
      switch status {
      case .unknown, .shouldRequest:
        return .notDetermined
      case .unnecessary:
        return .prompted
      @unknown default:
        return .notDetermined
      }
    } catch {
      return .notDetermined
    }
  }

  public static func requestAuthorization() async throws -> HealthKitAuthorizationState {
    guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
    let store = HKHealthStore()
    try await store.requestAuthorization(toShare: [], read: readTypes)
    return await authorizationState()
  }
}
