import CoreLocation
import SwiftUI
import UIKit

struct SpeedometerView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var tripSession: TripSession
    @EnvironmentObject private var demo: DemoMode
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("speedUnit") private var storedUnit = SpeedUnit.kilometersPerHour.rawValue
    @AppStorage("dashboardShowsMotionStatus") private var showsMotionStatus = true
    @AppStorage("dashboardShowsGPSStatus") private var showsGPSStatus = true

    #if DEBUG
    /// Debug-only hooks for the simulator snapshot workflow. They are compiled
    /// out of Release builds and never touch measurement or recording.
    private let snapshotOpensSettings = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-settings")
    private let snapshotOpensDiagnostics = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-diagnostics")
    private let snapshotOpensDemo = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-demo")
    private let snapshotStartsDemo = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-demo-live")
    private let snapshotPausesDemo = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-demo-paused")
    private let snapshotResumesDemo = ProcessInfo.processInfo.arguments.contains("-velora-snapshot-demo-resumed")
    #endif

    private var unit: SpeedUnit {
        SpeedUnit(rawValue: storedUnit) ?? .kilometersPerHour
    }

    private var reading: SpeedReading {
        tripSession.speedReading
    }

    /// Snapshot-only speed override. It changes presentation and nothing else:
    /// the engine, recorder and trip session never see this value.
    private var snapshotSpeedMetersPerSecond: Double? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-velora-snapshot-speed"),
              arguments.indices.contains(index + 1),
              let kilometersPerHour = Double(arguments[index + 1]),
              kilometersPerHour >= 0 else { return nil }
        return kilometersPerHour / 3.6
        #else
        return nil
        #endif
    }

    private var hasReading: Bool {
        if snapshotSpeedMetersPerSecond != nil { return true }
        return reading.metersPerSecond != nil && reading.source != .unavailable
    }

    private var displayedSpeed: String {
        if let snapshotSpeedMetersPerSecond {
            return unit.formattedSpeed(snapshotSpeedMetersPerSecond)
        }
        guard let metersPerSecond = reading.metersPerSecond else { return "—" }
        return unit.formattedSpeed(metersPerSecond)
    }

    private var gaugeSpeed: Double {
        if let snapshotSpeedMetersPerSecond {
            return unit.speed(fromMetersPerSecond: snapshotSpeedMetersPerSecond)
        }
        guard let metersPerSecond = reading.metersPerSecond else { return 0 }
        return unit.speed(fromMetersPerSecond: metersPerSecond)
    }

    private var gaugeScale: GaugeScale {
        GaugeScale.make(for: unit)
    }

    private var gaugeProgress: Double {
        min(max(gaugeSpeed / gaugeScale.maximum, 0), 1)
    }

    private var gpsPresentation: GPSStatusPresentation {
        GPSStatusPresentation.make(
            for: locationService.status,
            tripState: tripSession.state,
            startUpdatesCallCount: locationService.startUpdatesCallCount
        )
    }

    private var motionPresentation: MotionPresentation {
        MotionPresentation.make(
            state: tripSession.motionState,
            tripState: tripSession.state,
            statusConflict: tripSession.statusConflict,
            decisionConflict: tripSession.decisionConflict,
            hasGaps: tripSession.hasDistanceCoverageGaps
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let gaugeDiameter = gaugeDiameter(for: geometry.size)

            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        DashboardHeader(
                            state: tripSession.state,
                            isDemo: tripSession.isSimulatedSession,
                            demoDetail: demo.isRunning ? demo.rateLabel : nil,
                            onOpenSettings: { tripSession.showingSettings = true }
                        )

                        SpeedGauge(
                            progress: gaugeProgress,
                            valueText: displayedSpeed,
                            unitTitle: unit.title,
                            unitSpokenTitle: unit.spokenTitle,
                            isLive: hasReading,
                            diameter: gaugeDiameter,
                            scale: gaugeScale,
                            isSimulated: tripSession.isSimulatedSession
                        )
                        .padding(.top, 10)

                        // The status cards are display-only. Hiding them never touches
                        // LocationService, SpeedEngine, TripRecorder or the time ledger.
                        if showsMotionStatus || showsGPSStatus {
                            VStack(spacing: 12) {
                                if showsMotionStatus {
                                    MotionStatusCard(presentation: motionPresentation)
                                }

                                if showsGPSStatus {
                                    GPSStatusCard(
                                        presentation: gpsPresentation,
                                        authorizationStatus: locationService.authorizationStatus,
                                        servicesEnabled: locationService.servicesEnabled,
                                        showsPermissionAction: !tripSession.isSimulatedSession,
                                        onRequestPermission: { locationService.requestPermission() },
                                        onOpenSettings: openAppSettings
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }

                        MetricGrid(
                            maximumSpeedMetersPerSecond: tripSession.maximumSpeedMetersPerSecond,
                            averageSpeedMetersPerSecond: tripSession.averageSpeedMetersPerSecond,
                            distanceMeters: tripSession.distanceMeters,
                            elapsedSeconds: tripSession.elapsedSeconds,
                            unit: unit,
                            hasCoverageGaps: tripSession.hasDistanceCoverageGaps
                        )
                        .padding(.top, 12)

                        Spacer(minLength: 12)

                        DriveControls(
                            state: tripSession.state,
                            animationsEnabled: !reduceMotion,
                            onStart: {
                                switch controlTarget(for: .start) {
                                case .demo: demo.start()
                                case .live: tripSession.start(using: locationService)
                                }
                            },
                            onPause: {
                                switch controlTarget(for: .pause) {
                                case .demo: demo.pause()
                                case .live: tripSession.pause(locationService: locationService)
                                }
                            },
                            onResume: {
                                switch controlTarget(for: .resume) {
                                case .demo: demo.resume()
                                case .live: tripSession.resume(locationService: locationService)
                                }
                            },
                            onReset: {
                                switch controlTarget(for: .reset) {
                                case .demo: demo.reset()
                                case .live: tripSession.reset(locationService: locationService)
                                }
                            }
                        )
                        .equatable()
                        .frame(maxWidth: 560)
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, 4)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .safeAreaPadding(.bottom, 8)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .sheet(isPresented: $tripSession.showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(AppTheme.Radius.xlarge)
        }
        #if DEBUG
        // Snapshot-only presentation. A constant binding keeps the debug cover
        // visible for the simulator capture; Release builds exclude this block.
        .fullScreenCover(isPresented: .constant(snapshotOpensDiagnostics)) {
            NavigationStack {
                GPSDiagnosticsView()
            }
        }
        .task {
            if snapshotOpensSettings { tripSession.showingSettings = true }
        }
        .fullScreenCover(isPresented: .constant(snapshotOpensDemo)) {
            NavigationStack {
                DemoControlsView()
            }
        }
        .task {
            if snapshotOpensDemo {
                demo.enableForSnapshot()
            }
            if snapshotStartsDemo {
                demo.enableForSnapshot()
                demo.setRate(5)
                demo.start()

                if snapshotPausesDemo {
                    try? await Task.sleep(for: .seconds(2))
                    demo.pause()
                } else if snapshotResumesDemo {
                    try? await Task.sleep(for: .seconds(1))
                    demo.pause()
                    try? await Task.sleep(for: .milliseconds(300))
                    demo.resume()
                }
            }
        }
        #endif
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                locationService.refreshAuthorization()
                if tripSession.state == .running,
                   locationService.canReceiveLocation,
                   !locationService.isReceivingUpdates {
                    locationService.startUpdates()
                }
                tripSession.updateElapsed()
            }
        }
        .onChange(of: locationService.authorizationStatus) { _, status in
            if (status == .authorizedWhenInUse || status == .authorizedAlways),
               tripSession.state == .running {
                locationService.startUpdates()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, tripSession.state == .running {
                if demo.hasSession {
                    demo.pause()
                } else {
                    tripSession.pause(locationService: locationService)
                }
            }
        }
    }

    private func controlTarget(for action: TripControlAction) -> TripControlTarget {
        TripControlRouting.target(
            for: action,
            demoEnabled: demo.isEnabled,
            demoSessionActive: demo.hasSession
        )
    }

    private func gaugeDiameter(for size: CGSize) -> CGFloat {
        let widthLimit = size.width - (AppTheme.Spacing.lg * 2)
        let heightLimit = max(240, size.height * 0.36)
        return max(220, min(widthLimit, heightLimit, 360))
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
