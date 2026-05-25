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
        sensorStatus = "Starting sensors"
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
        sensorWatchdogTimer?.invalidate()
        sensorWatchdogTimer = nil
        hrQueryStartedAt = nil
        lastHeartRateSampleAt = nil
        heartRateRestartCount = 0
        payloadTimer?.cancel()
        payloadTimer = nil
        motionDeviationSamples.removeAll()
        motionCountBuffer = 0
        hrSamplesBuffer.removeAll()
        mockTimer?.cancel()
        mockTimer = nil
        sensorStatus = "Sensors stopped"
    }
    
    func startRealSensors() {
        motionDeviationSamples.removeAll()
        motionCountBuffer = 0
        hrSamplesBuffer.removeAll()
        heartRateRestartCount = 0
        sensorStatus = "Starting HR + motion"
        enableHeartRateBackgroundDelivery()
        
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50 Hz
            motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
                guard let self = self, let data = data else { return }
                
                let magnitude = sqrt(pow(data.acceleration.x, 2) + pow(data.acceleration.y, 2) + pow(data.acceleration.z, 2))
                let deviation = abs(magnitude - 1.0)

                self.motionDeviationSamples.append(deviation)
                if deviation >= self.motionThreshold {
                    self.motionCountBuffer += 1
                }
            }
        }

        payloadTimer = Timer.publish(every: payloadInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.compileAndTransmitPayload()
            }
        
        startHeartRateQuery(reason: "initial")
        startSensorWatchdog()
    }

    func startHeartRateQuery(reason: String) {
        if let query = hrQuery {
            healthStore.stop(query)
            hrQuery = nil
        }

        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let startDate = Date().addingTimeInterval(-120)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        hrQueryStartedAt = Date()
        sensorStatus = "HR query \(reason)"
        
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

    func startSensorWatchdog() {
        sensorWatchdogTimer?.invalidate()
        sensorWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkHeartRateWatchdog()
        }
    }

    func checkHeartRateWatchdog() {
        guard sensorsRunning else { return }
        guard !stopMonitoringIfAlarmDeadlineReached() else { return }
        guard let hrQueryStartedAt else { return }

        let now = Date()
        let hasFreshHR = lastHeartRateSampleAt.map { now.timeIntervalSince($0) <= 90 } ?? false
        if hasFreshHR {
            sensorStatus = "HR active"
            return
        }

        let queryAge = now.timeIntervalSince(hrQueryStartedAt)
        guard queryAge >= 75 else {
            sensorStatus = "Waiting HR \(Int(queryAge))s"
            return
        }

        guard heartRateRestartCount < 3 else {
            sensorStatus = "Error: HR sensor silent"
            updatePipelineState(.recording, detail: "Error: HR sensor silent")
            return
        }

        heartRateRestartCount += 1
        sensorStatus = "Restarting HR query \(heartRateRestartCount)"
        startHeartRateQuery(reason: "watchdog \(heartRateRestartCount)")
    }
    
    func processHRSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        let newValues = quantitySamples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        
        DispatchQueue.main.async {
            guard !newValues.isEmpty else { return }
            self.hrSamplesBuffer.append(contentsOf: newValues)
            self.lastHeartRateSampleAt = Date()
            self.sensorStatus = "HR active (\(newValues.count) samples)"
        }
    }
    
    func compileAndTransmitPayload() {
        guard !stopMonitoringIfAlarmDeadlineReached() else { return }

        let motionVariance = standardDeviation(for: motionDeviationSamples)
        let payload = SensorPayload(
            id: UUID(),
            timestamp: Date(),
            hrSamples: hrSamplesBuffer,
            motionCount: motionCountBuffer,
            accelerometerVariance: motionVariance,
            isMockData: false
        )
        
        hrSamplesBuffer.removeAll()
        motionDeviationSamples.removeAll()
        motionCountBuffer = 0
        
        transmit(payload: payload)
        processPayloadForLocalSmartWake(payload)
        refreshDiagnosticCounters()
        if payload.hrSamples.isEmpty && sensorsRunning {
            checkHeartRateWatchdog()
        }
        
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

        guard WatchPhoneSyncConfiguration.isPhoneSyncEnabled else {
            DispatchQueue.main.async {
                self.lastPayloadSent = "Captured at \(payload.timestamp.formatted(date: .omitted, time: .standard)), HR count: \(payload.hrSamples.count), Watch only"
            }
            return
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
