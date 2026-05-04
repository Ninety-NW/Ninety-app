import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    // MARK: - Reliable Payload Delivery

    var pendingPayloadsURL: URL? {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = supportDirectory.appendingPathComponent("Ninety", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("watch_pending_payloads.json")
    }

    func restorePendingPayloadQueue() {
        guard let url = pendingPayloadsURL else { return }

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        guard
            let data = try? Data(contentsOf: url),
            let restored = try? JSONDecoder().decode([PendingPayloadEnvelope].self, from: data)
        else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        pendingPayloads = Array(restored.suffix(maxPendingPayloads))
        if !pendingPayloads.isEmpty {
            replayStatusText = "Recovered \(pendingPayloads.count) pending payloads"
            updatePipelineState(.deliveringBacklog, detail: "Recovered \(pendingPayloads.count) pending payloads")
        }
    }

    func prepareForNewSession() {
        clearAlarmTracking()
        resetLocalAnalysis()
        clearPendingPayloadQueue()
        replayStatusText = "No backlog activity"
        updatePipelineState(.idle)
    }

    func invalidateRuntimeSessionIfNeeded() {
        if runtimeSession?.state == .running || runtimeSession?.state == .scheduled {
            suppressNextRuntimeInvalidation = true
            runtimeSession?.invalidate()
        }
        runtimeSession = nil
    }

    func clearScheduledAlarmAndMonitoring(
        detail: String,
        state: WatchPipelineState,
        keepHapticsRunning: Bool = false
    ) {
        if !keepHapticsRunning {
            invalidateRuntimeSessionIfNeeded()
            HapticWakeUpManager.shared.stop()
        }
        clearAlarmTracking(preserveLocalAlarmRecord: keepHapticsRunning)
        stopSensors()
        resetLocalAnalysis()
        clearPendingPayloadQueue()
        updatePipelineState(state, detail: detail)
        sendWatchStatusUpdate(sessionState)
    }

    func handleScheduledAlarmReached(reason: String) {
        let phoneReachable = wcSession?.activationState == .activated && wcSession?.isReachable == true
        
        // Start the silent Watch phase of the same Ninety alarm locally.
        startWatchHapticWakePhase()
        sendTriggerAlarmMessage()

        if phoneReachable {
            clearScheduledAlarmAndMonitoring(
                detail: "Watch smart wake active",
                state: .completed,
                keepHapticsRunning: true
            )
        } else {
            // Watch-only path: haptics are the available alert surface.
            clearScheduledAlarmAndMonitoring(
                detail: reason,
                state: .completed,
                keepHapticsRunning: true
            )
        }
    }

    func enqueuePendingPayload(_ payload: SensorPayload) {
        guard !pendingPayloads.contains(where: { $0.payload.id == payload.id }) else { return }

        pendingPayloads.append(
            PendingPayloadEnvelope(
                payload: payload,
                enqueuedAt: Date(),
                lastAttemptAt: nil,
                deliveryAttempts: 0,
                deferredDeliveryQueued: false
            )
        )

        if pendingPayloads.count > maxPendingPayloads {
            pendingPayloads.removeFirst(pendingPayloads.count - maxPendingPayloads)
        }

        savePendingPayloadQueue()
        sendWatchStatusUpdate(sessionState)
    }

    func acknowledgePayloads(withIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }

        let acknowledgedIDs = Set(ids)
        let previousCount = pendingPayloads.count
        pendingPayloads.removeAll { acknowledgedIDs.contains($0.payload.id) }

        guard pendingPayloads.count != previousCount else { return }

        savePendingPayloadQueue()
        let removedCount = previousCount - pendingPayloads.count
        replayStatusText = "Acked \(removedCount), pending \(pendingPayloads.count)"
        connectionStatus = pendingPayloads.isEmpty ? "Phone reachable" : "Phone reachable, pending \(pendingPayloads.count)"

        if pendingPayloads.isEmpty {
            if isActivelyMonitoring {
                updatePipelineState(.recording, detail: "Recording")
            } else if readyScheduledStartDate != nil {
                updatePipelineState(.scheduled, detail: readyScheduleDescription ?? "Scheduled")
            } else if pendingScheduledStartDate != nil {
                updatePipelineState(.scheduled, detail: pendingScheduleDescription ?? "Scheduled")
            } else {
                updatePipelineState(.idle)
            }
        }

        sendWatchStatusUpdate(sessionState)
    }

    func flushPendingPayloadsIfNeeded(force: Bool = false) {
        guard !pendingPayloads.isEmpty else { return }
        guard let session = wcSession, session.activationState == .activated else { return }

        let now = Date()
        if
            !force,
            let lastBacklogFlushDate,
            now.timeIntervalSince(lastBacklogFlushDate) < minimumBacklogFlushInterval
        {
            return
        }

        let batchCount = min(backlogReplayBatchSize, pendingPayloads.count)
        let indices = Array(pendingPayloads.indices.prefix(batchCount))
        guard !indices.isEmpty else { return }

        lastBacklogFlushDate = now
        updatePipelineState(.deliveringBacklog, detail: "Replaying \(batchCount)/\(pendingPayloads.count) payloads")
        replayStatusText = "Replaying \(batchCount)/\(pendingPayloads.count) payloads"
        sendPendingPayloads(at: indices, reason: "Backlog replay")
    }

    func sendPendingPayloads(at indices: [Int], reason: String) {
        guard let session = wcSession, session.activationState == .activated else { return }
        guard !indices.isEmpty else { return }

        let reachable = session.isReachable
        let now = Date()
        var queueDidChange = false
        var sentCount = 0

        for index in indices {
            guard pendingPayloads.indices.contains(index) else { continue }
            guard let encoded = try? JSONEncoder().encode(pendingPayloads[index].payload) else { continue }

            pendingPayloads[index].lastAttemptAt = now
            pendingPayloads[index].deliveryAttempts += 1
            queueDidChange = true

            let dict: [String: Any] = ["payloadData": encoded]
            if !pendingPayloads[index].deferredDeliveryQueued {
                session.transferUserInfo(dict)
                pendingPayloads[index].deferredDeliveryQueued = true
            }

            if reachable {
                session.sendMessage(dict, replyHandler: nil) { [weak self] error in
                    DispatchQueue.main.async {
                        self?.connectionStatus = "Live send failed: \(error.localizedDescription)"
                    }
                }
            }

            sentCount += 1
        }

        if queueDidChange {
            savePendingPayloadQueue()
        }

        connectionStatus = reachable ? "Phone reachable, pending \(pendingPayloads.count)" : "Phone unavailable, pending \(pendingPayloads.count)"
        replayStatusText = "\(reason): sent \(sentCount), pending \(pendingPayloads.count)"
        lastPayloadSent = "\(reason): sent \(sentCount), pending \(pendingPayloads.count)"
        sendWatchStatusUpdate(sessionState)
    }

    func savePendingPayloadQueue() {
        guard let url = pendingPayloadsURL else { return }

        if pendingPayloads.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }

        do {
            let data = try JSONEncoder().encode(pendingPayloads)
            try data.write(to: url, options: [.atomic])
        } catch {
            connectionStatus = "Queue save failed: \(error.localizedDescription)"
        }
    }

    func clearPendingPayloadQueue() {
        pendingPayloads.removeAll()
        savePendingPayloadQueue()
    }

}
