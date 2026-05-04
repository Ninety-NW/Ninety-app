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
        motionDeviationSamples.removeAll()
        motionCountBuffer = 0
        hrSamplesBuffer.removeAll()
        mockTimer?.cancel()
        mockTimer = nil
    }
    
    func startRealSensors() {
        motionDeviationSamples.removeAll()
        motionCountBuffer = 0
        hrSamplesBuffer.removeAll()
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
