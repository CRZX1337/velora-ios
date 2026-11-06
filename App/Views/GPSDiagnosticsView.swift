import SwiftUI

struct GPSDiagnosticsView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var tripSession: TripSession

    private var diagnostics: SpeedEngineDiagnostics {
        tripSession.engineDiagnostics
    }

    private var presentation: GPSStatusPresentation {
        GPSStatusPresentation.make(
            for: locationService.status,
            tripState: tripSession.state,
            startUpdatesCallCount: locationService.startUpdatesCallCount
        )
    }

    private var windowsAreDisjoint: Bool {
        Set(diagnostics.currentSampleIDs)
            .intersection(Set(diagnostics.previousSampleIDs))
            .isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            DiagnosticStatusBanner(presentation: presentation)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, 10)
                .padding(.bottom, 4)

            Form {
                Section {
                    DiagnosticRow("Authorization", authorizationDescription)
                    DiagnosticRow("Precise Location", preciseLocationDescription)
                    DiagnosticRow("Location Services", locationService.servicesEnabled ? "Enabled" : "Disabled")
                    DiagnosticRow("Updates", locationService.isReceivingUpdates ? "Active" : "Inactive")
                } header: {
                    Text("Status")
                }

                Section {
                    DiagnosticRow("Location Callbacks", "\(locationService.locationCallbackCount)")
                    DiagnosticRow("startUpdatingLocation", startUpdatesDescription)
                    DiagnosticRow("Last Callback", formattedTime(locationService.lastCallbackDate))
                    DiagnosticRow("Last Raw Fix", formattedTime(locationService.lastRawFixDate))
                    DiagnosticRow("Last Accuracy", formattedAccuracy(locationService.lastReportedAccuracy))
                    DiagnosticRow("Raw Speed", formattedSpeed(locationService.lastReportedSpeed))
                    DiagnosticRow("Speed Accuracy", formattedSpeedAccuracy(locationService.lastReportedSpeedAccuracy))
                } header: {
                    Text("Reception")
                }

                Section {
                    DiagnosticRow("Source", readingSourceText)
                    DiagnosticRow("Displayed Value", formattedSpeed(tripSession.speedReading.metersPerSecond))
                    DiagnosticRow("Age", formattedAge(tripSession.speedReading.age))
                    DiagnosticRow("Held", tripSession.speedReading.isHeld ? "Yes" : "No")
                } header: {
                    Text("Speed Reading")
                }

                Section {
                    DiagnosticRow("Overall Status", verdictText(tripSession.motionState))
                    DiagnosticRow("Position Window", verdictText(tripSession.positionMotionStatus))
                    DiagnosticRow("Distance Segment", verdictText(tripSession.segmentMotionStatus))
                    DiagnosticRow("Native Reading", verdictText(tripSession.nativeMotionStatus))
                    DiagnosticRow("Status Conflict", tripSession.statusConflict ? "Yes" : "No")
                    DiagnosticRow("Decision Conflict", tripSession.decisionConflict ? "Yes" : "No")
                    DiagnosticRow("Last Segment Resolution", resolutionText(tripSession.lastSegmentResolution))
                } header: {
                    Text("Movement Decision")
                }

                Section {
                    DiagnosticRow("Samples", "\(diagnostics.sampleCount)")
                    DiagnosticRow("Time Span", String(format: "%.1f s", diagnostics.windowSpan))
                    DiagnosticRow("Speed", String(format: "%.2f m/s", diagnostics.speed))
                    DiagnosticRow("SE(speed)", String(format: "%.2f m/s", diagnostics.standardError))
                    DiagnosticRow("Resolution", String(format: "%.2f m/s", diagnostics.resolution))
                    DiagnosticRow("Evidence Margin", String(format: "%.2f m/s", diagnostics.margin))
                    DiagnosticRow("RSS0", String(format: "%.4f", diagnostics.rss0))
                    DiagnosticRow("RSS1", String(format: "%.4f", diagnostics.rss1))
                    DiagnosticRow("F", diagnostics.fStatistic.map { String(format: "%.2f", $0) } ?? "—")
                    DiagnosticRow("Median Accuracy", formattedAccuracy(diagnostics.medianAccuracy))
                    DiagnosticRow("Reason", diagnostics.reason)
                    DiagnosticRow("Disjoint Windows", windowsAreDisjoint ? "Yes" : "No")
                    DiagnosticRow("Native Reason", diagnostics.nativeReason)
                    DiagnosticRow("Decimated Samples", "\(diagnostics.decimatedSamples)")
                } header: {
                    Text("Regression Window")
                }

                Section {
                    DiagnosticRow("Distance", String(format: "%.1f m", tripSession.distanceMeters))
                    DiagnosticRow("Active Time", formattedDuration(tripSession.elapsedSeconds))
                    DiagnosticRow("Covered (Driving)", formattedDuration(tripSession.committedSeconds))
                    DiagnosticRow("Covered (Stationary)", formattedDuration(tripSession.stationarySeconds))
                    DiagnosticRow("Gap Duration", formattedDuration(tripSession.gapSeconds))
                    DiagnosticRow("Gaps", "\(tripSession.gapCount)")
                    DiagnosticRow("Pending Time", formattedDuration(tripSession.pendingSeconds))
                    DiagnosticRow("Pending Samples", "\(tripSession.pendingSamples)")
                    DiagnosticRow("Average", averageText)
                    DiagnosticRow("Ledger Balanced", tripSession.ledgerBalanced ? "Yes" : "No")
                    DiagnosticRow("Duplicate Resolutions", "\(tripSession.doubleResolutionAttempts)")
                } header: {
                    Text("Distance & Coverage")
                }

                if locationService.lastErrorCode != nil {
                    Section {
                        DiagnosticRow("Last Error", lastErrorDescription)
                    } header: {
                        Text("Error")
                    }
                }

                Section {
                    Text("No coordinates or addresses are shown or stored.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

            }
            .scrollContentBackground(.hidden)
        }
        .background(AppBackground())
        .navigationTitle("GPS Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.Colors.accent)
    }

    // MARK: - Formatting

    private var readingSourceText: String {
        switch tripSession.speedReading.source {
        case .native: return "Native"
        case .derived: return "Derived"
        case .held: return "Held"
        case .unavailable: return "Unavailable"
        }
    }

    private var averageText: String {
        let value = tripSession.averageSpeedMetersPerSecond
        let formatted = String(format: "%.2f m/s", value)
        return tripSession.hasDistanceCoverageGaps ? "≈ \(formatted) (incomplete)" : formatted
    }

    private var authorizationDescription: String {
        switch locationService.authorizationStatus {
        case .notDetermined: "Not Determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedWhenInUse: "While Using the App"
        case .authorizedAlways: "Always"
        @unknown default: "Unknown"
        }
    }

    private var preciseLocationDescription: String {
        guard locationService.servicesEnabled,
              locationService.authorizationStatus == .authorizedWhenInUse
                || locationService.authorizationStatus == .authorizedAlways
        else { return "Unavailable" }

        return locationService.accuracyAuthorization == .fullAccuracy
            ? "Enabled"
            : "Disabled (Approximate)"
    }

    private var startUpdatesDescription: String {
        guard locationService.startUpdatesCallCount > 0 else { return "No" }
        return "\(locationService.startUpdatesCallCount)× · \(formattedTime(locationService.lastStartUpdatesDate))"
    }

    private var lastErrorDescription: String {
        guard let code = locationService.lastErrorCode else { return "—" }
        let domain = locationService.lastErrorDomain ?? "CLError"
        let description = locationService.lastErrorDescription ?? "Unknown"
        return "\(domain) \(code): \(description)"
    }

    private func verdictText(_ verdict: MotionVerdict) -> String {
        switch verdict {
        case .moving: return "Moving"
        case .stationary: return "Stationary"
        case .stabilizing: return "Stabilizing"
        }
    }

    private func resolutionText(_ resolution: SegmentResolution?) -> String {
        guard let resolution else { return "—" }
        switch resolution {
        case .committed: return "Committed"
        case .stationaryZero: return "Stationary (zero)"
        case .gap: return "Gap"
        }
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }

    private func formattedAccuracy(_ accuracy: Double?) -> String {
        guard let accuracy, accuracy.isFinite, accuracy >= 0 else { return "—" }
        return "±\(String(format: "%.1f", accuracy)) m"
    }

    private func formattedSpeed(_ speed: Double?) -> String {
        guard let speed, speed.isFinite, speed >= 0 else { return "—" }
        return "\(String(format: "%.2f", speed)) m/s"
    }

    private func formattedSpeedAccuracy(_ accuracy: Double?) -> String {
        guard let accuracy, accuracy.isFinite, accuracy >= 0 else { return "—" }
        return "±\(String(format: "%.2f", accuracy)) m/s"
    }

    private func formattedAge(_ age: Double) -> String {
        guard age.isFinite else { return "—" }
        return String(format: "%.1f s", age)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The one persistent status summary above the raw numbers. It answers the
/// question the rows below only detail, without hiding any measurement.
private struct DiagnosticStatusBanner: View {
    let presentation: GPSStatusPresentation

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: presentation.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(presentation.tint)
                .frame(width: 44, height: 44)
                .background(presentation.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A diagnostics row that keeps the label quiet and the value precise:
/// tabular digits, right aligned, allowed to wrap instead of truncating.
private struct DiagnosticRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
