import SwiftFitActivity
import Foundation
import HealthKit

public enum WorkoutFITExporter {
  public static func encode(bundle: WorkoutExportBundle) throws -> Data {
    let data = try WorkoutFITEncoder.encode(bundle: bundle)
    _ = try FITActivityParser.parse(bytes: Array(data))
    return data
  }

  public static func encode(workout: HKWorkout, store: HKHealthStore) async throws -> (Data, String) {
    let bundle = try await HealthKitWorkoutLoader.exportBundle(for: workout, store: store)
    let data = try encode(bundle: bundle)
    let filename = Self.filename(for: bundle)
    return (data, filename)
  }

  public static func filename(for bundle: WorkoutExportBundle) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: bundle.startDate)
    return "\(day)-\(bundle.sport.filenameComponent).fit"
  }
}
