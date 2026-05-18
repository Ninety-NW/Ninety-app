import Foundation

extension WatchSensorManager {
    func restoreLocalDiagnosticLogs() {
        guard let data = UserDefaults.standard.data(forKey: Self.watchEpochDiagnosticLogKey) else {
            epochDiagnostics = []
            return
        }

        guard let restored = try? JSONDecoder().decode([WatchEpochDiagnostic].self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.watchEpochDiagnosticLogKey)
            epochDiagnostics = []
            return
        }

        epochDiagnostics = Array(restored.suffix(Self.maxLocalDiagnosticLogs))
    }

    func appendLocalDiagnostic(_ diagnostic: WatchEpochDiagnostic) {
        epochDiagnostics.append(diagnostic)
        if epochDiagnostics.count > Self.maxLocalDiagnosticLogs {
            epochDiagnostics.removeFirst(epochDiagnostics.count - Self.maxLocalDiagnosticLogs)
        }
        persistLocalDiagnosticLogs()
        refreshDiagnosticCounters()
    }

    func clearDiagnosticLogs() {
        epochDiagnostics.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.watchEpochDiagnosticLogKey)
        refreshDiagnosticCounters()
    }

    func persistLocalDiagnosticLogs() {
        guard let data = try? JSONEncoder().encode(epochDiagnostics) else { return }
        UserDefaults.standard.set(data, forKey: Self.watchEpochDiagnosticLogKey)
    }

    func refreshDiagnosticCounters() {
        validEpochCount = epochHistory.count
        let queued = WatchPhoneSyncConfiguration.isPhoneSyncEnabled ? ", \(pendingPayloads.count) queued" : ""
        diagnosticBufferSummary = "\(currentEpochPayloads.count) payloads\(queued)"

        if smartWakeTriggered {
            smartWakeConfirmationSummary = "Triggered"
        } else if isConfirmingSmartWake {
            smartWakeConfirmationSummary = "\(confirmationBuffer.count)/\(confirmationRequired)"
        } else {
            smartWakeConfirmationSummary = "0/\(confirmationRequired)"
        }
    }
}
