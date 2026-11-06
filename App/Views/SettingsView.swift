import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var tripSession: TripSession
    @EnvironmentObject private var demo: DemoMode
    @AppStorage("speedUnit") private var storedUnit = SpeedUnit.kilometersPerHour.rawValue
    @AppStorage("dashboardShowsMotionStatus") private var showsMotionStatus = true
    @AppStorage("dashboardShowsGPSStatus") private var showsGPSStatus = true

    private var currentStatus: GPSStatusPresentation {
        GPSStatusPresentation.make(
            for: locationService.status,
            tripState: tripSession.state,
            startUpdatesCallCount: locationService.startUpdatesCallCount
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.velora.app"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Speed", selection: $storedUnit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("Applies to the gauge and all trip data.")
                }

                Section {
                    Toggle("Show Movement Status", isOn: $showsMotionStatus)
                    Toggle("Show GPS Status", isOn: $showsGPSStatus)
                } header: {
                    Text("Dashboard")
                } footer: {
                    Text("These cards only change the display. GPS measurement, movement detection and distance recording continue unchanged.")
                }

                Section {
                    Toggle("Demo Mode", isOn: Binding(
                        get: { demo.isEnabled },
                        set: { demo.setEnabled($0) }
                    ))

                    LabeledContent("Status", value: demo.statusText)

                    if demo.isEnabled {
                        NavigationLink {
                            DemoControlsView()
                        } label: {
                            Label("Simulation Controls", systemImage: "testtube.2")
                        }

                        Button(demo.isRunning || (demo.isPaused && !demo.isStopped) ? "Stop Simulation" : "Start Simulation") {
                            if demo.isRunning || (demo.isPaused && !demo.isStopped) {
                                demo.stop()
                            } else {
                                demo.start()
                            }
                        }
                        .disabled(tripSession.state != .idle && !demo.hasSession)
                    }
                } header: {
                    Text("Developer & Demo Mode")
                } footer: {
                    Text("Simulated trips run through the same speed, motion and distance pipeline. They are labeled DEMO MODE on the dashboard, never stored, and never leave the device.")
                }

                Section {
                    NavigationLink {
                        GPSDiagnosticsView()
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(currentStatus.tint)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("GPS Diagnostics")

                                Text(currentStatus.title)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Text(locationService.isReceivingUpdates ? "Active" : "Inactive")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }

                    LabeledContent("Accuracy", value: accuracyText)
                } header: {
                    Text("Location")
                }

                Section {
                    Label("Location data stays on this device.", systemImage: "lock.shield")
                        .font(.subheadline.weight(.medium))
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("GPS Diagnostics never shows coordinates or addresses.")
                }

                Section {
                    LabeledContent("App", value: "Velora")
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    LabeledContent("Bundle Identifier", value: bundleIdentifier)
                } header: {
                    Text("About Velora")
                } footer: {
                    Text("Native GPS Speedometer for iOS")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .tint(AppTheme.Colors.accent)
        }
    }

    private var accuracyText: String {
        guard let accuracy = locationService.horizontalAccuracy,
              accuracy.isFinite,
              accuracy >= 0
        else { return "—" }
        return "±\(String(format: "%.1f", accuracy)) m"
    }
}
