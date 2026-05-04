# **Architecture and Implementation Strategy for a Distributed iOS/watchOS Smart Alarm System**

## **Executive Overview**

The development of the "Ninety" smart alarm system presents a sophisticated distributed computing challenge within the Apple ecosystem. The core objective of the application is to awaken the user at the optimal physiological moment within a predefined time window, thereby mitigating sleep inertia and maximizing daytime alertness. Achieving this requires precise identification of the user's sleep phase—specifically avoiding Deep Sleep in favor of Light or Rapid Eye Movement (REM) sleep—and triggering a system-level alarm event upon detection.

To satisfy the stringent battery constraints of wearable devices, the system architecture mandates a strict separation of concerns. The Apple Watch, constrained by a limited battery capacity and thermal envelope, acts solely as an edge sensor node, capturing raw biological markers. The companion iPhone, equipped with superior computational resources and larger energy reserves, serves as the primary processing engine, executing heuristic algorithms and managing the scheduling logic.

This comprehensive architectural document details the exact Apple frameworks, classes, and programmatic methods required to construct this system. It critically investigates the feasibility of utilizing Apple’s native HealthKit sleep phase recognition (such as built-in REM detection) for real-time alarm triggers. Furthermore, it outlines the specific background execution privileges required on watchOS, the low-latency inter-device communication protocols necessary to bridge the hardware, the iOS background computing lifecycle, and the deployment of the newly introduced AlarmKit framework to execute infallible wake events.

## **Part I: Physiological Context and Native HealthKit Sleep Classification**

A fundamental requirement of the Ninety application is the ability to discriminate between distinct physiological states during the user's specified wake window. To understand the implementation, it is necessary to first understand how Apple classifies sleep and how this data is represented within the developer frameworks.

### **The Sleep Analysis Data Model**

The gold standard for clinical sleep staging is polysomnography (PSG), a process that utilizes electroencephalography (EEG) for brainwaves, electrocardiogram (ECG) for heart activity, and electromyography for muscle movement to categorize sleep into Awake, REM, and Non-REM stages (N1, N2, N3).1 Because the Apple Watch cannot measure brainwaves, it approximates these stages using a proprietary machine-learning algorithm that relies on photoplethysmography (PPG) for heart rate and heart rate variability (HRV), combined with a 3-axis accelerometer for micro-movement sensing.1

Within the iOS and watchOS developer ecosystem, these classifications are centralized within the HealthKit framework, specifically represented by the HKCategoryValueSleepAnalysis enumeration.3 Apple provides highly specific identifiers to represent the user's physiological state, allowing developers to query historical sleep data.

The following table details the mapping of native HealthKit enumerations to their physiological counterparts and their relevance to a smart alarm trigger:

| HealthKit Enumeration Value | Physiological Mapping | Alarm Trigger Relevance | Description |
| :---- | :---- | :---- | :---- |
| HKCategoryValueSleepAnalysis.awake | Conscious / Active | Highly Optimal | The user is awake or experiencing a brief micro-awakening. Triggering an alarm here ensures zero sleep inertia.3 |
| HKCategoryValueSleepAnalysis.asleepCore | Light/Intermediate (N1, N2) | Optimal | Represents the majority of the sleep cycle. Characterized by lowered temperature and steady heart rate. Ideal for waking if REM or Awake states are unavailable.3 |
| HKCategoryValueSleepAnalysis.asleepDeep | Slow-Wave Sleep (N3) | Highly Suboptimal | The deepest stage of sleep, crucial for physical recovery. Waking a user during this stage causes severe, prolonged sleep inertia (grogginess).3 |
| HKCategoryValueSleepAnalysis.asleepREM | Rapid Eye Movement (REM) | Optimal | Characterized by brain activity resembling wakefulness, variable heart rate, and muscle atonia. Waking during REM generally results in high cognitive alertness.1 |
| HKCategoryValueSleepAnalysis.inBed | Environmental State | Neutral | Tracks the total duration the user spends in bed, acting as an overarching wrapper that encompasses all other overlapping sleep stage samples.3 |

Historically, developers utilized a broader HKCategoryValueSleepAnalysis.asleep value. However, Apple formally deprecated this generic value in favor of the granular stage-based enumerations or the fallback asleepUnspecified value for instances where sensor data is too noisy to determine a specific stage.3

To interact with this data, developers instantiate an HKObjectType.categoryType(forIdentifier:.sleepAnalysis).9 Because a user can only be in one specific sleep stage at a given millisecond, HealthKit structure dictates that detailed samples (Core, Deep, REM) cannot overlap each other, though they will concurrently overlap the broader inBed sample.3 Accessing this historical data is achieved using an HKSampleQuery parameterized with an NSCompoundPredicate to filter by date range and specific enumeration values.9

### **Accuracy and Validation of Apple Watch Sleep Staging**

When relying on these enumerations, it is crucial to understand the inherent accuracy of the hardware. Apple updated its validation data in October 2025, incorporating foundation models developed using data from the Apple Heart and Movement Study as part of the iOS 26 and watchOS 26 updates.6

According to the clinical confusion matrix derived from Apple's validation against polysomnography, the Apple Watch is highly proficient at detecting sleep overall but possesses specific error margins when differentiating internal stages.1 For example, the algorithm correctly identifies Deep Sleep approximately 62% of the time, but will confuse Deep Sleep for Core (Light) Sleep 38% of the time.6 Furthermore, independent validation studies highlight that consumer wearables often overestimate light sleep while underestimating deep sleep, and can sometimes exhibit rapid, fluctuating jumps between stages before settling on a final classification.12

These accuracy margins are entirely acceptable for retrospective health analysis. However, as the following section will detail, the methodology Apple uses to achieve this accuracy introduces systemic latency that completely precludes the use of native HealthKit sleep stages for real-time smart alarm execution.

## **Part II: The Latency Constraint and Real-Time Apple Watch Sleep Staging**

A core directive of the Ninety application's requirements is to investigate the feasibility of utilizing Apple’s built-in recognition of sleep phases (specifically .asleepREM or .asleepCore) to trigger the alarm. A thorough architectural analysis reveals that relying on native HealthKit sleep stage categorization for a real-time smart alarm is biologically and computationally impossible due to systemic delays, batching mechanisms, and aggressive background throttling.13

### **Algorithmic Epoch Batching and Contextual Delay**

The fundamental barrier to real-time native sleep staging is how the classification algorithm operates. The Apple Watch does not assess sleep instantaneously. Instead, the time-series accelerometer and photoplethysmography data serve as inputs to an algorithm that classifies the signal into 30-second windows, known as epochs.1

Crucially, sleep physiology is not a localized event. To accurately classify a specific 30-second epoch as REM or Deep Sleep, the machine learning model requires surrounding contextual data—meaning it must analyze the epochs that occurred several minutes *before* and several minutes *after* the target window.1 Because the algorithm cannot predict the future, it must wait to collect succeeding epochs before it can confidently classify a preceding epoch.

Consequently, the Apple Watch does not write HKCategoryValueSleepAnalysis samples to the local HealthKit database in real-time.13 Instead, the data is held in memory, analyzed retrospectively, and then written to the Health store in large, coalesced batches.14 In many instances, the final, granular sleep stage breakdown is only fully processed and published to the database after the user manually disables their Sleep Focus, stands up, or reaches their scheduled wake time.3

### **The Failure of HKObserverQuery for Real-Time Execution**

Even if one were to assume the Apple Watch could theoretically write a sleep stage sample to the database instantaneously, the companion iOS application must still be notified of this write event to trigger the alarm. The standard mechanism for this is the HKObserverQuery, an API designed to set up a long-running background task that watches the HealthKit store and alerts the application when matching data is saved or removed.16

To enable background wake-ups for an observer query, developers must invoke the enableBackgroundDelivery(for:frequency:withCompletion:) method on the HKHealthStore.18 The frequency parameter dictates the maximum rate at which the system will wake the iOS application in response to new data. Developers naturally attempt to use HKUpdateFrequency.immediate to ensure real-time delivery.19

However, iOS imposes strict, non-negotiable limitations on background delivery to preserve battery life.14 The operating system treats the updateHandler of an HKObserverQuery as purely advisory.23 Official documentation and extensive developer testing reveal the following critical roadblocks:

1. **System-Enforced Throttling:** The system transparently enforces maximum frequency caps regardless of the developer's requested frequency. For many high-frequency data types, the operating system aggressively throttles the background wake-up frequency to a maximum of once per hour (HKUpdateFrequency.hourly).14  
2. **Opportunistic Delivery:** HealthKit delivers updates opportunistically. If the iPhone is locked, in Low Power Mode, or operating under memory and CPU pressure, the background notification is delayed, coalesced, or entirely dropped.14  
3. **Unreliable Callbacks:** Callbacks may be triggered inconsistently, and the Health app will sometimes cease notifying the parent application entirely if the background updates are deemed too frequent or if the application fails to quickly execute the completionHandler provided in the callback.14

Therefore, attempting to use an HKObserverQuery looking for an .asleepREM sample to fire an immediate alarm is architecturally invalid.13 The data will either not be written in time, or the iOS application will be throttled and fail to wake up to read it.

### **The Required Heuristic Pivot**

Because native HealthKit classifications are inaccessible for real-time triggers, the Ninety application must abandon the idea of querying .asleepREM. Instead, the system must establish a proprietary data pipeline. The Apple Watch must be utilized strictly as a raw sensor collector, gathering high-frequency heart rate and accelerometer data.13 This raw data must be immediately streamed to the iPhone, where a custom heuristic algorithm running on the iOS device infers the user's current sleep state dynamically.13 The subsequent sections detail the execution of this exact pipeline.

## **Part III: watchOS Edge Node Architecture and Sensor Acquisition**

To feed the iOS computational node, the Apple Watch must act as a continuous sensor collector during the specific 30-minute wake window defined by the user. Operating continuously in the background on watchOS is a highly restricted privilege due to the extreme physical limitations of the device's battery.26 Under normal conditions, watchOS aggressively suspends applications the moment the user lowers their wrist, completely halting code execution.27 Overcoming this requires the deployment of specialized background sessions.

### **Discarding HKWorkoutSession and HKLiveWorkoutBuilder**

Historically, the only mechanism available to developers to force the Apple Watch to remain active indefinitely in the background was to instantiate an HKWorkoutSession paired with an HKLiveWorkoutBuilder.29 An active workout session fine-tunes the Apple Watch sensors, forces continuous high-frequency heart rate sampling, and completely prevents the application from entering a suspended state.29 Furthermore, workout sessions support native mirroring to a companion iOS app via the startMirroringToCompanionDevice() method, natively waking the iPhone in the background to receive real-time metrics.29

While HKWorkoutSession appears highly attractive for gathering continuous biological data, utilizing it for a sleep application introduces catastrophic side effects that fundamentally ruin the user's health data ecosystem:

1. **Activity Ring Corruption:** An HKWorkoutSession explicitly signals to the operating system that the user is actively exercising.29 If activated during sleep, it overrides the native Sleep Focus, alters the basal metabolic rate calorie calculations, and floods the HealthKit store with false exercise minutes.29 Users would frequently receive "Exercise goal reached" notifications in the middle of the night while completely motionless in bed.35  
2. **Unnecessary Battery Drain:** Workout sessions are designed for intense physical activity and maintain all sensors (including GPS depending on the configuration) at maximum polling rates.29 Running this continuously for 30 minutes overnight significantly degrades battery life.35

### **The Optimal Solution: WKExtendedRuntimeSession**

To address the need for specific, non-workout background tasks, Apple introduced the WKExtendedRuntimeSession API.27 This framework allows an application to continue communicating with Bluetooth devices, processing data, and accessing sensors after the screen turns off, without classifying the activity as a workout.27

The framework provides four distinct session types, each tailored to a specific use case with unique runtime limits. The following table delineates these types:

| Extended Runtime Session Type | Execution State | Time Limit | Primary Use Case |
| :---- | :---- | :---- | :---- |
| Self care | Frontmost | 10 Minutes | Brief emotional well-being activities (e.g., tooth brushing, hand washing).27 |
| Mindfulness | Frontmost | 1 Hour | Silent meditation sessions. Requires the app to be frontmost.27 |
| Physical therapy | Background | 1 Hour | Stretching or range-of-motion exercises. Does not require the app to be active on screen.27 |
| Smart alarm | Background | 30 Minutes | Scheduling a window to monitor heart rate and motion to determine optimal wake times.27 |

For the Ninety application, the WKExtendedRuntimeSessionTypeSmartAlarm is the exact, purpose-built API designed by Apple for this architectural requirement.27

#### **Architectural Advantages of the Smart Alarm Session**

The Smart Alarm session provides several crucial benefits that perfectly align with the system requirements:

1. **Precise Duration Limit:** The session permits a maximum of 30 minutes of continuous background execution.28 This duration directly corresponds to the standard industry practice of a 30-minute "wake window" (e.g., if the user sets their alarm for 7:00 AM, the window opens at 6:30 AM).  
2. **Unrestricted Sensor Access:** While active, the session explicitly grants the application the authority to query CMMotionManager for high-frequency accelerometer data and allows background reads of heart rate samples, all while the watch screen remains off and the user is deeply asleep.27  
3. **Future Scheduling Capability:** This is the most critical feature. Unlike all other session types that must be invoked immediately via session.start(), the Smart Alarm session exclusively supports the session.start(at: Date) method.37 This allows the iOS application to pass the wake window start time to the watchOS app hours in advance. The watchOS app can schedule the session, allowing the watch to remain completely dormant and preserve maximum battery life until the exact moment the wake window begins.39

#### **Implementation Lifecycle on watchOS**

To implement this architecture, the developer must first enable the "Smart Alarm" capability within the Xcode project's Background Modes.37 The operational lifecycle follows a strict sequence:

**1\. Instantiation and Scheduling:** When the user configures their alarm on the iPhone, the settings are transferred to the Apple Watch. The watchOS extension instantiates a WKExtendedRuntimeSession object and assigns a delegate conforming to WKExtendedRuntimeSessionDelegate.37 The app then invokes session.start(at: wakeWindowStartDate).37

**2\. Error Handling during Scheduling:** The developer must handle potential WKExtendedRuntimeSessionErrorCode exceptions during scheduling. For instance, the system will throw .scheduledTooFarInAdvance if the requested date is outside the system's permissible bounds, or .mustBeActiveToStartOrSchedule if the app attempts to schedule the session while the watchOS app is not in the foreground active state.40

**3\. Session Activation and Polling:** At the scheduled time, watchOS automatically wakes the application extension in the background. The delegate receives the extendedRuntimeSessionDidStart(\_:) callback.27 Upon receiving this callback, the application immediately spins up its sensor polling mechanisms:

* **Motion:** CMMotionManager is activated to stream 3-axis accelerometer data, allowing the system to detect gross motor shifts, micro-twitches, or absolute stillness.25  
* **Heart Rate:** Because an active HKWorkoutSession is not running to force continuous heart rate reads, the application must rely on the system's ambient heart rate polling. The app deploys an HKAnchoredObjectQuery targeting HKQuantityTypeIdentifier.heartRate. While ambient polling is less frequent than workout polling, it still captures periodic samples that are crucial for determining Heart Rate Variability (HRV).44

**4\. Session Invalidation:** The session naturally expires after 30 minutes, or the developer can manually terminate it early via session.invalidate() if the alarm is triggered.37 The delegate will receive extendedRuntimeSessionWillExpire(\_:) just before expiration to allow for cleanup tasks, followed by extendedRuntimeSession(\_:didInvalidateWith:error:).27

With the sensor data actively accumulating in memory on the Apple Watch, the next architectural challenge is transmitting this payload to the iPhone with zero latency.

## **Part IV: The Inter-Device Communication Pipeline (WatchConnectivity)**

The system requires an uninterrupted, low-latency pipeline to stream the raw biological markers from the active WKExtendedRuntimeSession on the watch to the iOS device for algorithmic processing. The WatchConnectivity framework is the dedicated Apple API for managing this transfer, relying entirely on the WCSession class.46

### **Evaluating Transmission Modalities**

The WCSession class provides multiple methods for transferring data, each with distinct behaviors regarding delivery guarantees, background Wake-ups, and latency. Choosing the correct method is paramount for a real-time smart alarm.

The following table contrasts the available WatchConnectivity data transfer methods:

| Transfer Method | Background Delivery Strategy | Latency | Suitability for Smart Alarm |
| :---- | :---- | :---- | :---- |
| updateApplicationContext(\_:) | Replaces the existing payload with the newest version. Delivered opportunistically in the background when system resources allow.48 | High (Minutes to Hours) | Completely Unsuitable. The system queues the data, and previous states are overwritten, losing continuous time-series data.48 |
| transferUserInfo(\_:) | Queues dictionaries sequentially in a FIFO (First In, First Out) manner. Delivered opportunistically in the background.46 | High (Minutes to Hours) | Unsuitable. While it preserves history, the opportunistic delivery means the alarm trigger payload may be delayed until the user is already awake.48 |
| sendMessage(\_:replyHandler:errorHandler:) | Requires the counterpart application to be reachable. Executes an immediate, interactive transfer. Sequences are strictly maintained.46 | Ultra-Low (Milliseconds) | Mandatory. This is the only method capable of real-time streaming to evaluate physiological states instantaneously.48 |

### **Implementing the Real-Time Stream via sendMessage**

To achieve near real-time streaming, the watchOS application must compile the accumulated heart rate and accelerometer data into small, optimized dictionary payloads (e.g., \`\`).48 Sending excessively large objects can result in timeouts; therefore, batching data into 5 to 10-second compressed increments is the optimal strategy.53

The watchOS application invokes:

Swift

WCSession.default.sendMessage(payload, replyHandler: nil) { error in   
    // Handle reachability or transmission errors  
}

Using the asynchronous sendMessage without a reply handler is sufficient for one-way streaming, provided the counterpart is reachable.48

### **Waking and Sustaining the iOS Application**

The most complex architectural hurdle in this pipeline is ensuring the iPhone application is awake to receive the sendMessage payloads. According to Apple's framework rules, if watchOS invokes sendMessage and the iOS application is suspended in the background, iOS will automatically wake the companion app to execute the session(\_:didReceiveMessage:) delegate method.48

However, this automated wake-up is extremely ephemeral. The iOS operating system grants the application merely a few seconds of execution time to process the incoming dictionary before aggressively suspending the app once again.55 If the watch sends data continuously every 5 seconds, this relentless cycle of waking, executing, and suspending creates massive computational overhead. The operating system's watchdog process will swiftly identify this behavior as resource abuse and terminate the iOS application entirely, breaking the pipeline.14

#### **The Daisy-Chained Background Task Architecture**

To resolve this, the iOS application must explicitly request an extended background execution task the moment the very first message arrives at the beginning of the 30-minute wake window.

When the initial sendMessage payload is intercepted by the WCSessionDelegate on the iPhone, the app must invoke the UIApplication API to request additional time:

Swift

let application \= UIApplication.shared  
var bgTask: UIBackgroundTaskIdentifier \=.invalid

bgTask \= application.beginBackgroundTask(withName: "SleepProcessing") {  
    // Expiration handler called by the OS if time runs out  
    application.endBackgroundTask(bgTask)  
    bgTask \=.invalid  
}

This specific API grants the iOS application a continuous block of background execution time—historically up to three minutes.54 As the 3-minute window nears its expiration, the iOS application must complete the current task via endBackgroundTask and immediately request a *new* background task upon the arrival of the next subsequent WatchConnectivity payload.54

By continuously requesting, expiring, and renewing these background tasks in response to the steady stream of incoming data from the watch, the iOS application successfully creates a "daisy-chain" of background execution.54 This architectural pattern maintains a stable, open execution socket, allowing the iPhone to run the intensive heuristic computations for the full 30-minute duration of the watch's WKExtendedRuntimeSession without being terminated by the OS.57

## **Part V: iOS Background Compute and Heuristic Inference**

With a persistent data stream established and the iPhone successfully held awake via background tasks, the iOS device assumes its role as the primary compute node. Delegating this algorithmic heavy lifting to the iPhone is structurally necessary; the Apple Watch processor is highly restricted, and running continuous machine-learning heuristics for 30 minutes on the wrist would cause unacceptable thermal throttling and battery degradation.26 The iPhone, equipped with significantly larger battery reserves and advanced neural engines, is uniquely suited for this continuous data processing.58

### **Heuristic Sleep Phase Inference**

Because native HealthKit categorization is delayed and unavailable for immediate querying 1, the iOS application must implement a proprietary classification algorithm. This algorithm ingests the raw arrays of CMMotionManager coordinates and HKQuantitySample heart rate values transmitted via sendMessage.25

Clinical validation of consumer wearables demonstrates that variations in heart rate, heart rate variability (HRV), and gross motor activity are highly reliable proxy discriminators for sleep states.12 The iOS application must apply a state-machine classification logic based on the following physiological markers:

1. **Deep Sleep Detection:** Characterized by an extremely stable, low resting heart rate, exceptionally high HRV, and absolute physical stillness (zero variance on the accelerometer).6 If the algorithm detects this state, it must actively inhibit the alarm to prevent severe sleep inertia.6  
2. **REM Sleep Detection:** Marked by a highly erratic heart rate that frequently resembles awake baseline levels, alongside muscle atonia (paralysis) punctuated by rapid micro-twitches that register as sharp, isolated spikes on the accelerometer.1 Detecting these erratic physiological markers signals an optimal wake window.1  
3. **Core/Light Sleep Detection:** Identified by minor postural shifts, a moderate and slightly variable heart rate, and increased overall accelerometer variance compared to the stillness of Deep Sleep.1 Waking during a natural transition from Deep to Core sleep is considered highly optimal and easily detectable via sustained movement.59

The iOS computational engine continuously calculates the rolling variance of the accelerometer payload and standard deviation of NN intervals (SDNN) from the heart rate payload to gauge autonomic nervous system activity.12

When the classification engine detects a sustained transition into a Light or REM sleep state, or if the algorithm detects a sudden spike in gross physical movement indicating a natural micro-awakening within the 30-minute wake window, it immediately signals the system to detonate the alarm.59 If the user remains biologically locked in Deep Sleep for the entirety of the 30-minute window, the algorithm defers to a hard limit, triggering the alarm at the absolute final minute to ensure the user meets their scheduled commitment.61

## **Part VI: Alarm Activation via AlarmKit (iOS 26\)**

Triggering an audible, unavoidable alarm from a backgrounded application has historically been one of the most restrictive and heavily policed challenges in iOS development. Prior to iOS 26, developers were forced to rely on standard UNUserNotificationCenter local notifications.62 These notifications were fundamentally flawed for an alarm clock context: they could be easily missed, silenced by hardware mute switches, suppressed entirely by Do Not Disturb or Sleep Focus settings, or casually dismissed with a single swipe without requiring the user to actually wake up.62

While Apple offers a "Critical Alerts" entitlement that bypasses silent switches, they tightly control its distribution, strictly reserving it for severe medical emergencies, public safety warnings, or extreme weather alerts. Apple explicitly rejects applications during the App Store review process that attempt to utilize Critical Alerts for standard alarm clocks.56

### **The AlarmKit Framework Revolution**

To resolve this long-standing limitation, Apple introduced the AlarmKit framework in iOS 26 (announced at WWDC 2025).63 AlarmKit provides third-party applications with the exact system-level privileges previously reserved exclusively for Apple’s native Clock and Reminders apps.63

Alarms deployed via AlarmKit possess the following unprecedented system-level capabilities:

1. **Guaranteed Prominence:** The alarm will break through Sleep Focus, Do Not Disturb, and the hardware silent switch, guaranteeing the user hears the alert regardless of their device state.63  
2. **Full-Screen Uninterruptible Presentation:** Instead of a transient notification banner, the alarm presents a full-screen, unmissable user interface with prominent "Snooze" and "Stop" interactions, identical to the native iOS alarm experience.62  
3. **Live Activities Integration:** Alarms integrate directly with the Lock Screen and Dynamic Island via the AlarmPresentationState structure, keeping the user informed of countdowns or active alerts even when the device is locked.63

### **Implementation and the Dual-Layer Scheduling Strategy**

Integrating AlarmKit into the Ninety application requires navigating specific authorization flows and employing a sophisticated scheduling strategy to ensure absolute reliability.

#### **1\. Authorization Requirements**

The application must explicitly prompt the user for permission to schedule alarms. The developer invokes AlarmManager.shared.requestAuthorization().71 Furthermore, the app's Info.plist must contain the NSAlarmKitUsageDescription key, featuring a localized string explaining the intent (e.g., "Ninety requires AlarmKit to ensure your wake-up alarm sounds even when your device is on silent").71 If this key is missing or blank, the system silently blocks the scheduling of any alarms.72

#### **2\. The Dual-Layer Scheduling Logic**

AlarmKit supports both absolute schedule-based alarms (e.g., specific dates and times) and relative countdown-based alarms (e.g., interval timers).64 For a smart alarm system relying on a distributed network of devices, a dual-layer scheduling approach provides the highest degree of reliability.61

**Layer One: The Absolute Failsafe** When the user configures their alarm (e.g., Target wake time: 7:30 AM, Wake Window: 30 minutes), the iOS application immediately schedules a deterministic, absolute alarm for the final target time (7:30 AM) using AlarmKit.61

Swift

let attributes \= AlarmAttributes(title: "Ninety Wake Up")  
let configuration \= AlarmManager.AlarmConfiguration(  
    schedule:.absolute(targetDate),   
    attributes: attributes,   
    sound:.named("WakeUpChime")  
)  
try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

This absolute alarm acts as an infallible, system-level safety net. In real-world scenarios, edge devices are prone to failure: the Apple Watch battery may deplete overnight, the Bluetooth connection may sever, or the iOS app may be force-closed by the user or terminated by the operating system due to memory pressure.61 By scheduling this alarm with the system daemon, AlarmKit guarantees delivery at exactly 7:30 AM irrespective of the application's lifecycle state or connection to the watch.63

**Layer Two: The Dynamic Heuristic Trigger** Meanwhile, during the active 6:30 AM to 7:00 AM wake window, the iOS app continuously analyzes the incoming WatchConnectivity data stream as detailed in Part V.37 If the algorithm detects an optimal wake event (e.g., at 6:42 AM), the iOS application immediately intervenes. It utilizes the AlarmManager to trigger the alarm instantaneously—either by aggressively modifying the schedule of the existing alarm to fire immediately, or by triggering a secondary zero-duration countdown alarm.71

Once the dynamic alarm fires and the user interacts with the full-screen interface to stop it, the application programmatically calls cancel on the AlarmManager for the original 7:30 AM failsafe, cleanly preventing a double-waking scenario.69

## **Conclusion**

The architecture of a highly precise, battery-efficient smart alarm system across the Apple ecosystem requires a deep understanding of framework limitations and strict adherence to distributed computing principles.

The investigation confirms that Apple's native HealthKit sleep staging (HKCategoryValueSleepAnalysis) cannot be utilized to trigger a real-time wake event. The systemic latency introduced by epoch batching and the aggressive throttling of background observer queries render it fundamentally incapable of sub-minute responsiveness.

Consequently, the optimal architectural solution relies on delegating raw sensor acquisition to the Apple Watch and heuristic computation to the iPhone. The watch utilizes the WKExtendedRuntimeSessionTypeSmartAlarm to awaken 30 minutes prior to the user's target time, polling raw heart rate and motion sensors with minimal battery overhead. This data is rapidly streamed via WCSession.sendMessage to the iPhone, which leverages a daisy-chain of UIBackgroundTaskIdentifier requests to maintain an open execution window in the background.

On the iOS node, a custom algorithmic heuristic analyzes the continuous stream of biological markers to detect physiological shifts indicative of non-Deep sleep states. Upon detecting the optimal waking moment, the application leverages the system-level privileges of the iOS 26 AlarmKit framework to break through Focus modes and deliver an unmissable, full-screen wake event. This sophisticated orchestration of Apple frameworks ensures maximum reliability, optimal physiological awakening, and absolute preservation of device battery life.

#### **Bibliografia**

1. Estimating Sleep Stages from Apple Watch, accesso eseguito il giorno aprile 2, 2026, [https://www.apple.com/health/pdf/Estimating\_Sleep\_Stages\_from\_Apple\_Watch\_Oct\_2025.pdf](https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf)  
2. How smartwatch heart monitoring saves lives: cases and global data \- Smartlet, accesso eseguito il giorno aprile 2, 2026, [https://smartlet.io/blogs/magazine/smartwatch-heart-monitoring-saves-lives-global-data-2026](https://smartlet.io/blogs/magazine/smartwatch-heart-monitoring-saves-lives-global-data-2026)  
3. HKCategoryValueSleepAnalysis | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)  
4. HKCategoryValueSleepAnalysis | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis?language=objc](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis?language=objc)  
5. HKCategoryValueSleepAnalysis, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis/asleepcore?language=objc](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis/asleepcore?language=objc)  
6. The average deep sleep on Apple Watch is 12% | Empirical Health, accesso eseguito il giorno aprile 2, 2026, [https://www.empirical.health/metrics/deep-sleep-percent](https://www.empirical.health/metrics/deep-sleep-percent)  
7. Problem with the Apple HealthKit to obtain accurate sleep data \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/78081993/problem-with-the-apple-healthkit-to-obtain-accurate-sleep-data](https://stackoverflow.com/questions/78081993/problem-with-the-apple-healthkit-to-obtain-accurate-sleep-data)  
8. Sleep length data not used \- This & That Support, accesso eseguito il giorno aprile 2, 2026, [https://support.bigpaua.com/t/sleep-length-data-not-used/556](https://support.bigpaua.com/t/sleep-length-data-not-used/556)  
9. Apple healthKit REM, Deep, Light sleep analysis \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/72570062/apple-healthkit-rem-deep-light-sleep-analysis](https://stackoverflow.com/questions/72570062/apple-healthkit-rem-deep-light-sleep-analysis)  
10. Retrieving Sleep Data with HealthKit in Swift | by Nathan Woolmore | Medium, accesso eseguito il giorno aprile 2, 2026, [https://medium.com/@nathan.woolmore/retrieving-sleep-data-with-healthkit-in-swift-e81829f4a726](https://medium.com/@nathan.woolmore/retrieving-sleep-data-with-healthkit-in-swift-e81829f4a726)  
11. sleepAnalysis | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis)  
12. Apple vs Oura: Sleep Stage Comparisons \- Terra API's, accesso eseguito il giorno aprile 2, 2026, [https://tryterra.co/blog/apple-vs-oura-sleep-stage-comparisons-94f359368e0a](https://tryterra.co/blog/apple-vs-oura-sleep-stage-comparisons-94f359368e0a)  
13. Apple Watch 9 \- Sleep Analysis : r/iOSProgramming \- Reddit, accesso eseguito il giorno aprile 2, 2026, [https://www.reddit.com/r/iOSProgramming/comments/1cshyau/apple\_watch\_9\_sleep\_analysis/](https://www.reddit.com/r/iOSProgramming/comments/1cshyau/apple_watch_9_sleep_analysis/)  
14. Some questions about background notifications and HealthKit : r/SwiftUI \- Reddit, accesso eseguito il giorno aprile 2, 2026, [https://www.reddit.com/r/SwiftUI/comments/1qkpjmi/some\_questions\_about\_background\_notifications\_and/](https://www.reddit.com/r/SwiftUI/comments/1qkpjmi/some_questions_about_background_notifications_and/)  
15. Apple Health \- iOS 16+ sleep handling \- Knowledge Base \- Validic Support, accesso eseguito il giorno aprile 2, 2026, [https://help.validic.com/space/VCS/3799646282](https://help.validic.com/space/VCS/3799646282)  
16. HKObserverQuery | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkobserverquery](https://developer.apple.com/documentation/healthkit/hkobserverquery)  
17. Executing Observer Queries | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/HealthKit/executing-observer-queries](https://developer.apple.com/documentation/HealthKit/executing-observer-queries)  
18. enableBackgroundDelivery(for:frequency:withCompletion:) | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery(for:frequency:withCompletion:)](https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery\(for:frequency:withCompletion:\))  
19. Working with HealthKit Background Delivery in iOS Development with Swift \- Medium, accesso eseguito il giorno aprile 2, 2026, [https://medium.com/@ios\_guru/working-with-healthkit-background-delivery-828d5144c5a8](https://medium.com/@ios_guru/working-with-healthkit-background-delivery-828d5144c5a8)  
20. Abnormal Background Delivery Frequency of HealthKit on Specific watchOS Devices, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/forums/thread/814914](https://developer.apple.com/forums/thread/814914)  
21. What's the expected frequency of HealthKit enableBackgroundDelivery: HKCategoryTypeIdentifier.sleepAnalysis \- Apple Developer Forums, accesso eseguito il giorno aprile 2, 2026, [https://origin-devforums.apple.com/forums/thread/790004](https://origin-devforums.apple.com/forums/thread/790004)  
22. Apple HealthKit \- Junction, accesso eseguito il giorno aprile 2, 2026, [https://docs.junction.com/wearables/guides/apple-healthkit](https://docs.junction.com/wearables/guides/apple-healthkit)  
23. What's the logic in HKObserverQuery background delivery? \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/37986435/whats-the-logic-in-hkobserverquery-background-delivery](https://stackoverflow.com/questions/37986435/whats-the-logic-in-hkobserverquery-background-delivery)  
24. Challenges With HKObserverQuery and Background App Refresh for HealthKit Data Handling | by Shemona Puri | Medium, accesso eseguito il giorno aprile 2, 2026, [https://medium.com/@shemona/challenges-with-hkobserverquery-and-background-app-refresh-for-healthkit-data-handling-8f84a4617499](https://medium.com/@shemona/challenges-with-hkobserverquery-and-background-app-refresh-for-healthkit-data-handling-8f84a4617499)  
25. Watch falls asleep during active HKWorkoutSession \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/75218315/watch-falls-asleep-during-active-hkworkoutsession](https://stackoverflow.com/questions/75218315/watch-falls-asleep-during-active-hkworkoutsession)  
26. Understanding Smartwatch Battery Utilization in the Wild \- PMC \- NIH, accesso eseguito il giorno aprile 2, 2026, [https://pmc.ncbi.nlm.nih.gov/articles/PMC7374306/](https://pmc.ncbi.nlm.nih.gov/articles/PMC7374306/)  
27. Using extended runtime sessions | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/WatchKit/using-extended-runtime-sessions](https://developer.apple.com/documentation/WatchKit/using-extended-runtime-sessions)  
28. WatchOS and the App Review: WKBackgroundModes : r/SwiftUI \- Reddit, accesso eseguito il giorno aprile 2, 2026, [https://www.reddit.com/r/SwiftUI/comments/15i7lxn/watchos\_and\_the\_app\_review\_wkbackgroundmodes/](https://www.reddit.com/r/SwiftUI/comments/15i7lxn/watchos_and_the_app_review_wkbackgroundmodes/)  
29. HKWorkoutSession | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkworkoutsession](https://developer.apple.com/documentation/healthkit/hkworkoutsession)  
30. Tracking workouts with HealthKit in iOS apps \- Create with Swift, accesso eseguito il giorno aprile 2, 2026, [https://www.createwithswift.com/tracking-workouts-with-healthkit-in-ios-apps/](https://www.createwithswift.com/tracking-workouts-with-healthkit-in-ios-apps/)  
31. HKLiveWorkoutBuilder | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder](https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder)  
32. Send Data from Apple watch to iPhone in background \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/35956038/send-data-from-apple-watch-to-iphone-in-background](https://stackoverflow.com/questions/35956038/send-data-from-apple-watch-to-iphone-in-background)  
33. startMirroringToCompanionDevice(completion:) | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/healthkit/hkworkoutsession/startmirroringtocompaniondevice(completion:)](https://developer.apple.com/documentation/healthkit/hkworkoutsession/startmirroringtocompaniondevice\(completion:\))  
34. Apple's API's Are Truly Awful (At Least Some Of Them) \- MzFit, accesso eseguito il giorno aprile 2, 2026, [https://mzfit.app/blog/apples\_apis\_are\_truly\_awful/](https://mzfit.app/blog/apples_apis_are_truly_awful/)  
35. HealthKit | Apple Developer Forums, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/forums/tags/healthkit/?page=4\&sortBy=oldest](https://developer.apple.com/forums/tags/healthkit/?page=4&sortBy=oldest)  
36. I tested Apple Watch sleep tracking to save you time and battery life | VentureBeat, accesso eseguito il giorno aprile 2, 2026, [https://venturebeat.com/technology/i-tested-apple-watch-sleep-tracking-to-save-you-time-and-battery-life](https://venturebeat.com/technology/i-tested-apple-watch-sleep-tracking-to-save-you-time-and-battery-life)  
37. WKExtendedRuntimeSession | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/watchkit/wkextendedruntimesession](https://developer.apple.com/documentation/watchkit/wkextendedruntimesession)  
38. How do I set up a WKExtendedRuntimeSession for a standalone watchOS app on Xcode 14? \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/75047880/how-do-i-set-up-a-wkextendedruntimesession-for-a-standalone-watchos-app-on-xcode](https://stackoverflow.com/questions/75047880/how-do-i-set-up-a-wkextendedruntimesession-for-a-standalone-watchos-app-on-xcode)  
39. WKExtendedRuntimeSession | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/watchkit/wkextendedruntimesession?changes=\_5\_9\&language=objc](https://developer.apple.com/documentation/watchkit/wkextendedruntimesession?changes=_5_9&language=objc)  
40. WKExtendedRuntimeSessionErr, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/watchkit/wkextendedruntimesessionerrorcode/notapprovedtoschedule?changes=\_4\_8,\_4\_8\&language=objc,objc](https://developer.apple.com/documentation/watchkit/wkextendedruntimesessionerrorcode/notapprovedtoschedule?changes=_4_8,_4_8&language=objc,objc)  
41. Extended Runtime Session in watchOS \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/60580245/extended-runtime-session-in-watchos](https://stackoverflow.com/questions/60580245/extended-runtime-session-in-watchos)  
42. How to run watch app in the background using WKExtendedRuntimeSession, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/74095753/how-to-run-watch-app-in-the-background-using-wkextendedruntimesession](https://stackoverflow.com/questions/74095753/how-to-run-watch-app-in-the-background-using-wkextendedruntimesession)  
43. WKExtendedRuntimeSessionErr, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/watchkit/wkextendedruntimesessionerrorcode](https://developer.apple.com/documentation/watchkit/wkextendedruntimesessionerrorcode)  
44. watchOS: How to use HKWorkoutSession without heart rate sensor \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/52827694/watchos-how-to-use-hkworkoutsession-without-heart-rate-sensor](https://stackoverflow.com/questions/52827694/watchos-how-to-use-hkworkoutsession-without-heart-rate-sensor)  
45. Apple Watch HealthKit Developer Tutorial: How to Build a Workout App \- Gorilla Logic, accesso eseguito il giorno aprile 2, 2026, [https://gorillalogic.com/apple-watch-healthkit-developer-tutorial-how-to-build-a-workout-app/](https://gorillalogic.com/apple-watch-healthkit-developer-tutorial-how-to-build-a-workout-app/)  
46. Watch Connectivity | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/WatchConnectivity](https://developer.apple.com/documentation/WatchConnectivity)  
47. WCSession | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/watchconnectivity/wcsession](https://developer.apple.com/documentation/watchconnectivity/wcsession)  
48. Three Ways to communicate via WatchConnectivity \- Teabyte, accesso eseguito il giorno aprile 2, 2026, [https://alexanderweiss.dev/blog/2023-01-18-three-ways-to-communicate-via-watchconnectivity](https://alexanderweiss.dev/blog/2023-01-18-three-ways-to-communicate-via-watchconnectivity)  
49. What is Apple watchconnectivity frequency and limits for a stream of messages, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/42886429/what-is-apple-watchconnectivity-frequency-and-limits-for-a-stream-of-messages](https://stackoverflow.com/questions/42886429/what-is-apple-watchconnectivity-frequency-and-limits-for-a-stream-of-messages)  
50. GitHub \- gfiumara/BackgroundWatchConnectivity: Trying to figure out WKWatchConnectivityRefreshBackgroundTask in watchOS 3., accesso eseguito il giorno aprile 2, 2026, [https://github.com/gfiumara/BackgroundWatchConnectivity](https://github.com/gfiumara/BackgroundWatchConnectivity)  
51. Reliable Background Recording on iOS & watchOS \- RisingStack blog, accesso eseguito il giorno aprile 2, 2026, [https://blog.risingstack.com/reliable-background-recording-on-ios-watchos/](https://blog.risingstack.com/reliable-background-recording-on-ios-watchos/)  
52. Watch Connectivity | Apple Developer Forums, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/forums/tags/watchconnectivity](https://developer.apple.com/forums/tags/watchconnectivity)  
53. watchOS 2 WatchConnectivity Time lag between Apple Watch and iPhone while sending data from one to another? \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/31574162/watchos-2-watchconnectivity-time-lag-between-apple-watch-and-iphone-while-sendin](https://stackoverflow.com/questions/31574162/watchos-2-watchconnectivity-time-lag-between-apple-watch-and-iphone-while-sendin)  
54. How to wake up iPhone app from watchOS 2? \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/31618550/how-to-wake-up-iphone-app-from-watchos-2](https://stackoverflow.com/questions/31618550/how-to-wake-up-iphone-app-from-watchos-2)  
55. Pushing background updates to your App | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)  
56. How to Set an iOS Critical Alert App for Realtime Processing? \- Stack Overflow, accesso eseguito il giorno aprile 2, 2026, [https://stackoverflow.com/questions/76830419/how-to-set-an-ios-critical-alert-app-for-realtime-processing](https://stackoverflow.com/questions/76830419/how-to-set-an-ios-critical-alert-app-for-realtime-processing)  
57. Using background tasks | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/WatchKit/using-background-tasks](https://developer.apple.com/documentation/WatchKit/using-background-tasks)  
58. Battery Drain Overnight While Using Apple Watch Sleep Tracking : r/iPhone17Pro \- Reddit, accesso eseguito il giorno aprile 2, 2026, [https://www.reddit.com/r/iPhone17Pro/comments/1qmfl0g/battery\_drain\_overnight\_while\_using\_apple\_watch/](https://www.reddit.com/r/iPhone17Pro/comments/1qmfl0g/battery_drain_overnight_while_using_apple_watch/)  
59. Best Sleep Trackers 2026: No Extra Hardware Needed \- Livity, accesso eseguito il giorno aprile 2, 2026, [https://livity-app.com/en/blog/best-sleep-trackers-2026-no-hardware](https://livity-app.com/en/blog/best-sleep-trackers-2026-no-hardware)  
60. 7 Apple Watch Health Features You're Not Using (2026) | Livity, accesso eseguito il giorno aprile 2, 2026, [https://livity-app.com/en/blog/apple-watch-health-features-you-are-not-using](https://livity-app.com/en/blog/apple-watch-health-features-you-are-not-using)  
61. Sleep Music Alarm \- App Store \- Apple, accesso eseguito il giorno aprile 2, 2026, [https://apps.apple.com/us/app/sleep-music-alarm/id1191086152](https://apps.apple.com/us/app/sleep-music-alarm/id1191086152)  
62. Feature Request: AlarmKit / Urgent Alarm support for time-critical to-dos : r/thingsapp, accesso eseguito il giorno aprile 2, 2026, [https://www.reddit.com/r/thingsapp/comments/1qyws0k/feature\_request\_alarmkit\_urgent\_alarm\_support\_for/](https://www.reddit.com/r/thingsapp/comments/1qyws0k/feature_request_alarmkit_urgent_alarm_support_for/)  
63. iOS 26 Makes Third-Party Alarm and Timer Apps Better \- MacRumors, accesso eseguito il giorno aprile 2, 2026, [https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)  
64. WWDC 2025 \- Wake up to the AlarmKit API \- iOS 26 \- DEV Community, accesso eseguito il giorno aprile 2, 2026, [https://dev.to/arshtechpro/wwdc-2025-wake-up-to-the-alarmkit-api-ios-26-4e67](https://dev.to/arshtechpro/wwdc-2025-wake-up-to-the-alarmkit-api-ios-26-4e67)  
65. Turn your Sleep Focus on or off on iPhone \- Apple Support, accesso eseguito il giorno aprile 2, 2026, [https://support.apple.com/guide/iphone/turn-sleep-focus-on-or-off-iph7cdb86325/ios](https://support.apple.com/guide/iphone/turn-sleep-focus-on-or-off-iph7cdb86325/ios)  
66. How to Activate Critical Alerts for iOS \- Help Center, accesso eseguito il giorno aprile 2, 2026, [https://help.emergent3.com/how-to-activate-critical-alerts-for-ios](https://help.emergent3.com/how-to-activate-critical-alerts-for-ios)  
67. How to Turn On Critical Alerts on iPhone (iOS 18\) \- YouTube, accesso eseguito il giorno aprile 2, 2026, [https://www.youtube.com/watch?v=ecfqdKZw5co](https://www.youtube.com/watch?v=ecfqdKZw5co)  
68. Wake up to the AlarmKit API | Documentation \- WWDC Notes, accesso eseguito il giorno aprile 2, 2026, [https://wwdcnotes.com/documentation/wwdcnotes/wwdc25-230-wake-up-to-the-alarmkit-api/](https://wwdcnotes.com/documentation/wwdcnotes/wwdc25-230-wake-up-to-the-alarmkit-api/)  
69. AlarmKit | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/AlarmKit](https://developer.apple.com/documentation/AlarmKit)  
70. AlarmKit | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/AlarmKit?changes=\_7\_\_7\&language=objc](https://developer.apple.com/documentation/AlarmKit?changes=_7__7&language=objc)  
71. Scheduling Alarms in iOS Apps with AlarmKit: A Complete Guide | by Manav | Medium, accesso eseguito il giorno aprile 2, 2026, [https://medium.com/@manavmanuprakash/scheduling-alarms-in-ios-apps-with-alarmkit-a-complete-guide-88b727f1c523](https://medium.com/@manavmanuprakash/scheduling-alarms-in-ios-apps-with-alarmkit-a-complete-guide-88b727f1c523)  
72. Scheduling an alarm with AlarmKit | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit)  
73. WWDC25: Wake up to the AlarmKit API | Apple \- YouTube, accesso eseguito il giorno aprile 2, 2026, [https://www.youtube.com/watch?v=t86tPExCAqc](https://www.youtube.com/watch?v=t86tPExCAqc)  
74. Alarm | Apple Developer Documentation, accesso eseguito il giorno aprile 2, 2026, [https://developer.apple.com/documentation/AlarmKit/Alarm](https://developer.apple.com/documentation/AlarmKit/Alarm)