import Foundation

/// Represents the raw data batch transmitted from the Apple Watch to the iPhone via WatchConnectivity.
struct SensorPayload: Codable {
    let id: UUID
    let timestamp: Date
    let hrSamples: [Double]
    let motionCount: Double
    let accelerometerVariance: Double
    let isMockData: Bool
}

/// A 30-second epoch already aggregated and classified on Apple Watch.
struct WatchEpochDiagnostic: Codable {
    let id: UUID
    let timestamp: Date
    let processedAt: Date
    let heartRateMean: Double
    let heartRateStd: Double
    let heartRateRange: Double
    let motionMagMean: Double
    let motionMagMax: Double
    let motionJerk: Double
    let rawStage: Int?
    let smoothedStage: Int?
    let stageTitle: String
    let isTestInjected: Bool
}
