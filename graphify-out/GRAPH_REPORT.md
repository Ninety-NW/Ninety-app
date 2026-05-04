# Graph Report - .  (2026-04-15)

## Corpus Check
- 29 files · ~57,698 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 242 nodes · 356 edges · 13 communities detected
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 20 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Sleep Data Processing|Sleep Data Processing]]
- [[_COMMUNITY_Watch Sensor & Communication|Watch Sensor & Communication]]
- [[_COMMUNITY_App Overview & Architecture|App Overview & Architecture]]
- [[_COMMUNITY_MVVM ViewModels|MVVM ViewModels]]
- [[_COMMUNITY_Diagnostics & Glass UI|Diagnostics & Glass UI]]
- [[_COMMUNITY_UI Views|UI Views]]
- [[_COMMUNITY_Alarm & Siri Integration|Alarm & Siri Integration]]
- [[_COMMUNITY_Watch Edge Sensor Node|Watch Edge Sensor Node]]
- [[_COMMUNITY_App Entry Points|App Entry Points]]
- [[_COMMUNITY_Liquid Glass Design System|Liquid Glass Design System]]
- [[_COMMUNITY_Background Comm Architecture|Background Comm Architecture]]
- [[_COMMUNITY_Brand Identity|Brand Identity]]
- [[_COMMUNITY_App Icons|App Icons]]

## God Nodes (most connected - your core abstractions)
1. `SleepSessionManager` - 31 edges
2. `WatchSensorManager` - 31 edges
3. `EdgeSensorNode` - 15 edges
4. `ScheduleViewModel` - 11 edges
5. `Heuristic Sleep Phase Inference` - 8 edges
6. `SleepStage` - 7 edges
7. `AppTheme` - 7 edges
8. `triggerDynamicAlarm()` - 6 edges
9. `TimeView` - 6 edges
10. `WatchAppDelegate` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Sleep Tracking` --semantically_similar_to--> `Smart Alarm System`  [INFERRED] [semantically similar]
  README.md → iOS_watchOS Sleep Tracking Technical Document.md
- `Ninety watchOS App Icon` --semantically_similar_to--> `Ninety iOS App Icon`  [INFERRED] [semantically similar]
  NinetyWatch Watch App/Assets.xcassets/AppIcon.appiconset/NinetyLogo-ezgif.com-resize.png → Ninety/Assets.xcassets/AppIcon.appiconset/NinetyLogo-ezgif.com-resize.png

## Hyperedges (group relationships)
- **Distributed Smart Alarm Pipeline** — techdoc_edge_sensor_node, techdoc_watchconnectivity, techdoc_iphone_compute_node, techdoc_alarmkit [EXTRACTED 0.95]
- **Background Execution Stack** — techdoc_wkextendedruntimesession, techdoc_daisy_chain_bg_tasks, techdoc_uibackgroundtaskidentifier [EXTRACTED 0.90]
- **Sleep Phase Classification** — techdoc_sleep_phase_awake, techdoc_sleep_phase_core, techdoc_sleep_phase_deep, techdoc_sleep_phase_rem [EXTRACTED 0.95]
- **Glass Composition & Morphing System** — liquidglassreference_glass_effect_container, liquidglassreference_glass_effect_id_morphing, liquidglassreference_glass_effect_union [EXTRACTED 0.90]

## Communities

### Community 0 - "Sleep Data Processing"
Cohesion: 0.11
Nodes (10): Int, EpochAggregate, FeatureVector, PredictionSnapshot, SleepSessionManager, SleepStage, nrem, rem (+2 more)

### Community 1 - "Watch Sensor & Communication"
Cohesion: 0.13
Nodes (3): Codable, SensorPayload, WatchSensorManager

### Community 2 - "App Overview & Architecture"
Cohesion: 0.08
Nodes (29): iOS 17 Compatibility, MVVM Pattern, Ninety App, Sleep Tracking, SwiftUI, AlarmKit Framework (iOS 26), AlarmManager, CMMotionManager (Accelerometer) (+21 more)

### Community 3 - "MVVM ViewModels"
Cohesion: 0.09
Nodes (15): CaseIterable, Identifiable, ObservableObject, ScheduleViewModel, SleepData, StorageKey, TimeView, day (+7 more)

### Community 4 - "Diagnostics & Glass UI"
Cohesion: 0.09
Nodes (13): ButtonStyle, DiagnosticsView, ButtonStyle, Glass, GlassButtonStyle, GlassEffectContainer, GlassVariant, clear (+5 more)

### Community 5 - "UI Views"
Cohesion: 0.11
Nodes (14): ContentView, ControlsView, DashboardView, OnboardingView, FuturisticButton, GlassPill, HorizonBackground, CustomWheelPicker (+6 more)

### Community 6 - "Alarm & Siri Integration"
Cohesion: 0.13
Nodes (14): AlarmMetadata, AppIntent, AppShortcutsProvider, NinetyShortcutsProvider, ScheduleWakeUpIntent, SleepHeuristicEngine, cancelSession(), createDefaultAttributes() (+6 more)

### Community 7 - "Watch Edge Sensor Node"
Cohesion: 0.2
Nodes (3): EdgeSensorNode, WCSessionDelegate, WKExtendedRuntimeSessionDelegate

### Community 8 - "App Entry Points"
Cohesion: 0.18
Nodes (6): App, NinetyApp, NinetyWatch_Watch_AppApp, WatchAppDelegate, NSObject, WKApplicationDelegate

### Community 9 - "Liquid Glass Design System"
Cohesion: 0.2
Nodes (10): Backward Compatibility iOS 26, Glass Button Styles, GlassEffectContainer, glassEffectID Morphing, glassEffect Modifier, glassEffectUnion, Interactive Glass Modifier, Liquid Glass Material (+2 more)

### Community 10 - "Background Comm Architecture"
Cohesion: 0.4
Nodes (5): Daisy-Chain Background Tasks, Rationale: sendMessage over Context/UserInfo, UIBackgroundTaskIdentifier, WatchConnectivity Framework, WCSession.sendMessage

### Community 11 - "Brand Identity"
Cohesion: 1.0
Nodes (2): Ninety Brand Logo, Ninety Logo Design Style

### Community 12 - "App Icons"
Cohesion: 1.0
Nodes (2): Ninety iOS App Icon, Ninety watchOS App Icon

## Knowledge Gaps
- **40 isolated node(s):** `wake`, `nrem`, `rem`, `regular`, `clear` (+35 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Brand Identity`** (2 nodes): `Ninety Brand Logo`, `Ninety Logo Design Style`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `App Icons`** (2 nodes): `Ninety iOS App Icon`, `Ninety watchOS App Icon`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SleepSessionManager` connect `Sleep Data Processing` to `App Entry Points`, `MVVM ViewModels`, `Alarm & Siri Integration`, `Watch Edge Sensor Node`?**
  _High betweenness centrality (0.185) - this node is a cross-community bridge._
- **Why does `WatchSensorManager` connect `Watch Sensor & Communication` to `App Entry Points`, `MVVM ViewModels`, `Watch Edge Sensor Node`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **What connects `wake`, `nrem`, `rem` to the rest of the system?**
  _40 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Sleep Data Processing` be split into smaller, more focused modules?**
  _Cohesion score 0.11 - nodes in this community are weakly interconnected._
- **Should `Watch Sensor & Communication` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._
- **Should `App Overview & Architecture` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._
- **Should `MVVM ViewModels` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._