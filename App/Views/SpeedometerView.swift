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

    private var gaugeState: GaugeState {
        if snapshotSpeedMetersPerSecond != nil { return .live }
        return GaugeState.make(
            status: locationService.status,
            tripState: tripSession.state,
            hasReading: hasReading
        )
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

    /// Demo playback feeds samples many times per second; its numeric roll is
    /// skipped so the digits settle instead of animating continuously.
    private var valueAnimationsEnabled: Bool {
        !reduceMotion && !tripSession.isSimulatedSession
    }

    var body: some View {
        dashboard
            .safeAreaBar(edge: .bottom) { tripControls }
            .modifier(TripFeedback(state: tripSession.state))
            .sheet(isPresented: $tripSession.showingSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(AppTheme.Radius.hero)
            }
            #if DEBUG
            .fullScreenCover(isPresented: .constant(snapshotOpensDiagnostics)) {
                NavigationStack {
                    GPSDiagnosticsView()
                }
            }
            .fullScreenCover(isPresented: .constant(snapshotOpensDemo)) {
                NavigationStack {
                    DemoControlsView()
                }
            }
            .task { await runSnapshotScenario() }
            #endif
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    scrollContent(
                        diameter: gaugeDiameter(for: geometry.size),
                        viewportHeight: geometry.size.height
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task { await keepMeasurementRunning() }
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

    private func scrollContent(diameter: CGFloat, viewportHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            gauge(diameter: diameter)
            statusSection
            metrics
            Spacer(minLength: AppTheme.Spacing.md)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.xxs)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth)
        .frame(maxWidth: .infinity)
        .frame(minHeight: viewportHeight, alignment: .top)
    }

    private var header: some View {
        DashboardHeader(
            state: tripSession.state,
            isDemo: tripSession.isSimulatedSession,
            demoDetail: demo.isRunning ? demo.rateLabel : nil,
            onOpenSettings: { tripSession.showingSettings = true }
        )
    }

    private func gauge(diameter: CGFloat) -> some View {
        SpeedGauge(
            speed: gaugeSpeed,
            valueText: displayedSpeed,
            unitTitle: unit.title,
            unitSpokenTitle: unit.spokenTitle,
            state: gaugeState,
            diameter: diameter,
            scale: gaugeScale,
            isSimulated: tripSession.isSimulatedSession
        )
        .padding(.top, AppTheme.Spacing.sm)
    }

    /// The status cards are display-only. Hiding them never touches
    /// LocationService, SpeedEngine, TripRecorder or the time ledger.
    @ViewBuilder
    private var statusSection: some View {
        if showsMotionStatus || showsGPSStatus {
            VStack(spacing: AppTheme.Spacing.sm) {
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
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    private var metrics: some View {
        MetricGrid(
            maximumSpeedMetersPerSecond: tripSession.maximumSpeedMetersPerSecond,
            averageSpeedMetersPerSecond: tripSession.averageSpeedMetersPerSecond,
            distanceMeters: tripSession.distanceMeters,
            elapsedSeconds: tripSession.elapsedSeconds,
            unit: unit,
            hasCoverageGaps: tripSession.hasDistanceCoverageGaps,
            animationsEnabled: valueAnimationsEnabled
        )
        .padding(.top, AppTheme.Spacing.sm)
    }

    // MARK: - Chrome

    private var tripControls: some View {
        DriveControls(
            state: tripSession.state,
            animationsEnabled: !reduceMotion,
            onStart: { perform(.start) },
            onPause: { perform(.pause) },
            onResume: { perform(.resume) },
            onReset: { perform(.reset) }
        )
        .equatable()
        .frame(maxWidth: AppTheme.Layout.maxContentWidth)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, AppTheme.Spacing.xs)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    private func perform(_ action: TripControlAction) {
        switch controlTarget(for: action) {
        case .demo:
            switch action {
            case .start: demo.start()
            case .pause: demo.pause()
            case .resume: demo.resume()
            case .reset: demo.reset()
            }
        case .live:
            switch action {
            case .start: tripSession.start(using: locationService)
            case .pause: tripSession.pause(locationService: locationService)
            case .resume: tripSession.resume(locationService: locationService)
            case .reset: tripSession.reset(locationService: locationService)
            }
        }
    }

    // MARK: - Lifecycle

    private func keepMeasurementRunning() async {
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

    #if DEBUG
    private func runSnapshotScenario() async {
        if snapshotOpensSettings { tripSession.showingSettings = true }
        if snapshotOpensDemo {
            demo.enableForSnapshot()
        }
        guard snapshotStartsDemo else { return }

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
    #endif

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
        return max(
            AppTheme.Layout.minGaugeDiameter,
            min(widthLimit, heightLimit, AppTheme.Layout.maxGaugeDiameter)
        )
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Haptics follow trip transitions, never GPS traffic. The conditions are
/// static, so the modifier stays cheap while the dashboard re-renders.
private struct TripFeedback: ViewModifier {
    let state: TripState

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .medium), trigger: state, condition: Self.didStart)
            .sensoryFeedback(.impact(weight: .light), trigger: state, condition: Self.didPause)
            .sensoryFeedback(.impact(weight: .light), trigger: state, condition: Self.didResume)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: state, condition: Self.didReset)
    }

    private static func didStart(_ previous: TripState, _ current: TripState) -> Bool {
        previous == .idle && current == .running
    }

    private static func didPause(_ previous: TripState, _ current: TripState) -> Bool {
        previous == .running && current == .paused
    }

    private static func didResume(_ previous: TripState, _ current: TripState) -> Bool {
        previous == .paused && current == .running
    }

    private static func didReset(_ previous: TripState, _ current: TripState) -> Bool {
        previous != .idle && current == .idle
    }
}
