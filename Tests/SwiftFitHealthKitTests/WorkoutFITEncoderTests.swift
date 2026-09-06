import Foundation
import SwiftFit
import SwiftFitActivity
import Testing

@testable import SwiftFitHealthKit

@Suite struct WorkoutFITEncoderTests {
  @Test func encodesStandardRecordFieldsAndValidCRCs() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let bundle = WorkoutExportBundle(
      startDate: start,
      endDate: start.addingTimeInterval(10),
      duration: 10,
      totalDistanceMeters: 50,
      totalEnergyKcal: 20,
      sport: .cycling(indoor: false),
      samples: [
        WorkoutSample(
          timestamp: start,
          heartRateBpm: 123,
          distanceMeters: 0,
          speedMps: 5.25,
          cadenceRpm: 84,
          powerWatts: 250,
          latitude: 40.75,
          longitude: -111.88,
          altitudeMeters: 1_300),
        WorkoutSample(
          timestamp: start.addingTimeInterval(10),
          heartRateBpm: 145,
          distanceMeters: 50,
          speedMps: 6.5,
          cadenceRpm: 91,
          powerWatts: 310,
          latitude: 40.751,
          longitude: -111.879,
          altitudeMeters: 1_290),
      ])

    let data = try WorkoutFITEncoder.encode(bundle: bundle)
    var options = FITDecodeOptions(validateFileCRC: true, validateHeaderCRC: true)
    let fit = try FITFile(data: data, options: options)
    #expect(fit.headerCRCValid)
    #expect(fit.fileCRCValid)

    let records = fit.messages.filter { $0.globalMessageNumber == FITGlobalMessage.record }
    #expect(records.count == 2)
    #expect(records[0].uint8Field(number: FITRecordField.heartRate) == 123)
    #expect(records[0].uint8Field(number: 4) == 84)
    #expect(records[0].uint16Field(number: 7) == 250)
    #expect(records[0].uint16Field(number: FITRecordField.speed) == 5_250)
    #expect(records[1].uint8Field(number: FITRecordField.heartRate) == 145)
    #expect(records[1].uint16Field(number: 7) == 310)

    let summary = try FITActivityParser.parse(bytes: Array(data))
    #expect(summary.points.count == 2)
    #expect(summary.points[0].heartRate == 123)
    #expect(summary.sport == .cycling)
    #expect(abs((summary.sessionDistanceMeters ?? 0) - 50) < 0.01)
  }

  @Test func producesNormalRecordHeadersForTimestampFirstDefinition() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let samples = (0..<100).map { index in
      WorkoutSample(
        timestamp: start.addingTimeInterval(Double(index)),
        heartRateBpm: UInt8(100 + index % 40),
        distanceMeters: Double(index) * 5,
        speedMps: 5)
    }
    let bundle = WorkoutExportBundle(
      startDate: start,
      endDate: start.addingTimeInterval(99),
      duration: 99,
      totalDistanceMeters: 495,
      totalEnergyKcal: nil,
      sport: .running(indoor: false),
      samples: samples)

    let data = try WorkoutFITEncoder.encode(bundle: bundle)
    let fit = try FITFile(data: data)
    let records = fit.messages.filter { $0.globalMessageNumber == FITGlobalMessage.record }
    #expect(records.count == 100)
    #expect(records.compactMap { $0.uint32Field(number: FITRecordField.timestamp) }.count == 100)
  }
}
