import Foundation

/// Represents the raw data batch transmitted from the Apple Watch to the iPhone via WatchConnectivity.
struct SensorPayload: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let hrSamples: [Double]
    let motionCount: Double
    let accelerometerVariance: Double
    let isMockData: Bool
}

/// A 30-second epoch already aggregated and classified on Apple Watch.
struct WatchEpochDiagnostic: Codable, Sendable {
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

enum AnalysisConstants {
    /// The maximum allowed time gap (in seconds) between sensor payloads before the ML analysis buffer is reset.
    static let maxSensorGapThreshold: TimeInterval = 300
}

extension Array where Element == Double {
    var mean: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let m = mean
        let variance = reduce(0) { partialResult, value in
            partialResult + pow(value - m, 2)
        } / Double(count)
        return sqrt(variance)
    }
}
