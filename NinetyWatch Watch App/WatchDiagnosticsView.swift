import SwiftUI

struct WatchDiagnosticsView: View {
    @ObservedObject var sensorManager: WatchSensorManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Text("Diagnostics")
                        .font(.system(.headline, design: .rounded).weight(.semibold))

                    Spacer()
                }

                diagnosticSection("Status") {
                    statusRow("Pipeline", sensorManager.sessionState)
                    statusRow("Runtime", sensorManager.runtimeStatus)
                    statusRow("Sensors", sensorManager.sensorStatus)
                    statusRow("Auto-launch", sensorManager.autoLaunchStatus)
                    statusRow("Model", sensorManager.watchModelStatus)
                    statusRow("Connection", sensorManager.connectionStatus)
                    statusRow("Last payload", sensorManager.lastPayloadSent)
                    statusRow("Epochs", "\(sensorManager.validEpochCount)")
                    statusRow("Buffer", sensorManager.diagnosticBufferSummary)
                    statusRow("Smart wake", sensorManager.smartWakeConfirmationSummary)
                }

                diagnosticSection("Epoch Summary") {
                    statusRow("Logged", "\(totalEpochLogs) total")
                    statusRow("Accepted", "\(acceptedEpochLogs) valid / green")
                    statusRow("Dropped", "\(missingHREpochLogs) missing HR, \(invalidHREpochLogs) invalid HR")
                    statusRow("Warm-up", "\(sensorManager.validEpochCount)/\(sensorManager.minimumEpochsForFeatures) active history")
                    statusRow("Warm-up logs", "\(warmupEpochLogs) warming, \(predictionEpochLogs) predictions")
                    statusRow("Rule", "Epochs with HR errors do not advance warm-up")
                    statusRow("Reset clue", resetClueText)
                }

                diagnosticSection("Epoch Processing") {
                    if sensorManager.epochDiagnostics.isEmpty {
                        Text("No epochs")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(sensorManager.epochDiagnostics.reversed()), id: \.id) { diagnostic in
                            WatchEpochDiagnosticRow(diagnostic: diagnostic)
                        }
                    }
                }

                Button {
                    sensorManager.clearDiagnosticLogs()
                } label: {
                    Text("Clear logs")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    var totalEpochLogs: Int {
        sensorManager.epochDiagnostics.count
    }

    var acceptedEpochLogs: Int {
        sensorManager.epochDiagnostics.filter { $0.errorMessage == nil }.count
    }

    var missingHREpochLogs: Int {
        sensorManager.epochDiagnostics.filter { $0.errorMessage == "Error: missing HR" }.count
    }

    var invalidHREpochLogs: Int {
        sensorManager.epochDiagnostics.filter { $0.errorMessage == "Error: invalid HR" }.count
    }

    var warmupEpochLogs: Int {
        sensorManager.epochDiagnostics.filter { $0.stageTitle.hasPrefix("Warming") }.count
    }

    var predictionEpochLogs: Int {
        sensorManager.epochDiagnostics.filter { $0.errorMessage == nil && $0.rawStage != nil }.count
    }

    var resetClueText: String {
        guard acceptedEpochLogs > sensorManager.validEpochCount else {
            return "Active history matches this run"
        }
        return "Logs exceed active history: process restart or >5m gap likely"
    }

    func diagnosticSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.92))

            VStack(alignment: .leading, spacing: 5) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.8)
                }
        }
    }

    func statusRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.72)
        }
    }
}

struct WatchEpochDiagnosticRow: View {
    let diagnostic: WatchEpochDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnostic.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 4)
                Text(stageText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(diagnostic.errorMessage == nil ? Color.green.opacity(0.9) : Color.red.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Text(metricsText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)

            if let error = diagnostic.errorMessage {
                Text(error)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red.opacity(0.95))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    var stageText: String {
        if let error = diagnostic.errorMessage {
            return error
        }

        let raw = stageName(diagnostic.rawStage)
        let smoothed = stageName(diagnostic.smoothedStage)
        if raw == "-" && smoothed == "-" {
            return diagnostic.stageTitle
        }
        return "raw \(raw) / smoothed \(smoothed)"
    }

    var metricsText: String {
        "HR \(format(diagnostic.heartRateMean))  motion \(format(diagnostic.motionMagMean))  jerk \(format(diagnostic.motionJerk))"
    }

    func stageName(_ rawValue: Int?) -> String {
        guard let rawValue, let stage = WatchSensorManager.WatchSleepStage(rawValue: rawValue) else {
            return "-"
        }
        return stage.title
    }

    func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
