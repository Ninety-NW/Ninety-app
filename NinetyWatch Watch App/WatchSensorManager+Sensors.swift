import Foundation
import WatchKit
import HealthKit
import CoreMotion
import WatchConnectivity
import Combine
import CoreML

extension WatchSensorManager {
    // MARK: - Sensor Acquisition
    
    func startSensors() {
        guard !sensorsRunning else { return }
        guard !stopMonitoringIfAlarmDeadlineReached() else { return }
        if localAnalysisStartDate == nil {
            localAnalysisStartDate = Date()
        }
        sensorsRunning = true
        #if targetEnvironment(simulator)
        startMockDataStream()
        #else
        startRealSensors()
        #endif
    }
    
    func stopSensors() {
        sensorsRunning = false
        motionManager.stopAccelerometerUpdates()
        if let query = hrQuery {
            healthStore.stop(query)
            hrQuery = nil
        }
        payloadTimer?.cancel()
        payloadTimer = nil
        // Clear motion buffers on their own serial queue to avoid racing with any
        // in-flight accelerometer callback that hasn't been cancelled yet.
        motionBufferQueue.sync {
            self.motionDeviationSamples.removeAll()
            self.motionCountBuffer = 0
        }
        hrSamplesBuffer.removeAll()
        mockTimer?.cancel()
        mockTimer = nil
    }
    
    func startRealSensors() {
        // Reset motion buffers through the same queue used by the accelerometer
        // handler, so any lingering callback from a previous session can't write
        // into buffers we're about to repurpose.
        motionBufferQueue.sync {
            self.motionDeviationSamples.removeAll()
            self.motionCountBuffer = 0
        }
        hrSamplesBuffer.removeAll()
        enableHeartRateBackgroundDelivery()
        
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50 Hz
            motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
                guard let self = self, let data = data else { return }

                let magnitude = sqrt(pow(data.acceleration.x, 2) + pow(data.acceleration.y, 2) + pow(data.acceleration.z, 2))
                let deviation = abs(magnitude - 1.0)

                // Serialise all writes to the shared motion buffers through
                // motionBufferQueue so compileAndTransmitPayload can snapshot
                // them safely from the main thread using .sync.
                self.motionBufferQueue.async {
                    self.motionDeviationSamples.append(deviation)
                    if deviation >= self.motionThreshold {
                        self.motionCountBuffer += 1
                    }
                }
            }
        }

        payloadTimer = Timer.publish(every: payloadInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.compileAndTransmitPayload()
            }
        
        // Start HR
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        
        hrQuery = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.processHRSamples(samples)
        }
        
        hrQuery?.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHRSamples(samples)
        }
        
        if let query = hrQuery {
            healthStore.execute(query)
        }
    }
    
    func processHRSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        let newValues = quantitySamples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        
        DispatchQueue.main.async {
            self.hrSamplesBuffer.append(contentsOf: newValues)
        }
    }
    
    func compileAndTransmitPayload() {
        guard !stopMonitoringIfAlarmDeadlineReached() else { return }

        // ── Snapshot motion buffers atomically on motionBufferQueue ──────────
        // The accelerometer handler appends to these via motionBufferQueue.async
        // at 50 Hz. A sync dispatch gives us an exclusive read-then-clear window
        // with no risk of a concurrent write during the snapshot.
        var motionSamplesSnapshot: [Double] = []
        var motionCountSnapshot: Double = 0
        motionBufferQueue.sync {
            motionSamplesSnapshot = self.motionDeviationSamples
            motionCountSnapshot   = self.motionCountBuffer
            self.motionDeviationSamples.removeAll(keepingCapacity: true)
            self.motionCountBuffer = 0
        }

        // ── Snapshot HR buffer (already on main thread) ──────────────────────
        // processHRSamples appends via DispatchQueue.main.async, so all writes
        // are serialised on main. swap() exchanges the buffer's internal storage
        // pointer in a single instruction — read and clear are truly indivisible,
        // with no gap where a pending async append could interleave.
        var hrSnapshot: [Double] = []
        swap(&hrSnapshot, &hrSamplesBuffer)

        // ── Build and transmit the payload ───────────────────────────────────
        let motionVariance = motionSamplesSnapshot.standardDeviation
        let payload = SensorPayload(
            id: UUID(),
            timestamp: Date(),
            hrSamples: hrSnapshot,
            motionCount: motionCountSnapshot,
            accelerometerVariance: motionVariance,
            isMockData: false
        )

        transmit(payload: payload)
        processPayloadForLocalSmartWake(payload)

        if let alarmDate = nextAlarmDate, Date() >= alarmDate {
            DispatchQueue.main.async {
                print("WATCH: Reached scheduled wake time.")
                self.handleScheduledAlarmReached(reason: "Alarm active (local deadline)")
            }
        }
    }

    
    func transmit(payload: SensorPayload) {
        if isActivelyMonitoring && pipelineState != .deliveringBacklog {
            updatePipelineState(.recording, detail: "Recording")
        }

        enqueuePendingPayload(payload)
        if let lastIndex = pendingPayloads.indices.last {
            sendPendingPayloads(at: [lastIndex], reason: "Live delivery")
        }

        DispatchQueue.main.async {
            self.lastPayloadSent = "Captured at \(payload.timestamp.formatted(date: .omitted, time: .standard)), HR count: \(payload.hrSamples.count), pending: \(self.pendingPayloads.count)"
        }
    }

}
