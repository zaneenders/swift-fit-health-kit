import Foundation
import HealthKit
import SwiftFit
import SwiftFitActivity

public enum WorkoutFITExporter {
  public static func encode(bundle: WorkoutExportBundle) throws -> Data {
    try encodedBundle(bundle).data
  }

  public static func encode(workout: HKWorkout, store: HKHealthStore) async throws -> (Data, String) {
    let export = try await export(workout: workout, store: store)
    return (export.data, export.filename)
  }

  public static func export(workout: HKWorkout, store: HKHealthStore) async throws -> WorkoutFITExport {
    let loaded = try await HealthKitWorkoutLoader.loadExportBundle(for: workout, store: store)
    let encoded = try encodedBundle(loaded.bundle)
    let diagnostics = WorkoutExportDiagnostics(
      routeCount: loaded.routeCount,
      routeLocationCount: loaded.routeLocationCount,
      mergedSampleCount: loaded.bundle.samples.count,
      mergedGPSCount: loaded.bundle.samples.filter(Self.hasGPS).count,
      encodedRecordCount: encoded.recordCount,
      encodedGPSCount: encoded.gpsCount
    )
    return WorkoutFITExport(
      data: encoded.data,
      filename: filename(for: loaded.bundle),
      diagnostics: diagnostics
    )
  }

  public static func filename(for bundle: WorkoutExportBundle) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: bundle.startDate)
    return "\(day)-\(bundle.sport.filenameComponent).fit"
  }

  private static func encodedBundle(
    _ bundle: WorkoutExportBundle
  ) throws -> (data: Data, recordCount: Int, gpsCount: Int) {
    let data = try WorkoutFITEncoder.encode(bundle: bundle)
    let summary = try FITActivityParser.parse(bytes: Array(data))
    return (
      data,
      summary.points.count,
      summary.points.filter { $0.lat != nil && $0.lon != nil }.count
    )
  }

  private static func hasGPS(_ sample: WorkoutSample) -> Bool {
    guard let latitude = sample.latitude, let longitude = sample.longitude else { return false }
    return latitude.isFinite && longitude.isFinite
  }
}
