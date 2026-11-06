import SwiftUI

struct DemoControlsView: View {
    @EnvironmentObject private var demo: DemoMode
    @EnvironmentObject private var tripSession: TripSession

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "testtube.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.Colors.warning.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(demo.statusText)
                            .font(AppTheme.Typography.statusTitle)

                        Text("Synthetic fixes, real pipeline.")
                            .font(AppTheme.Typography.statusDetail)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            } footer: {
                Text("The demo source feeds the same speed engine, motion confirmation, distance ledger and trip timer as live GPS. Simulated coordinates never leave this device.")
            }

            Section {
                Picker("Profile", selection: profileBinding) {
                    ForEach(DemoDriveProfile.allCases) { profile in
                        Label(profile.title, systemImage: profile.symbolName)
                            .tag(profile)
                    }
                }
                .disabled(demo.hasSession)

                Text(demo.profile.summary)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if demo.hasSession {
                    Text("Stop and reset the session to change the profile.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            } header: {
                Label("Driving Profile", systemImage: "road.lanes")
            }

            Section {
                Picker("Simulation Speed", selection: rateBinding) {
                    ForEach(DemoDriveConfiguration.supportedRates, id: \.self) { rate in
                        Text(rateLabel(rate)).tag(rate)
                    }
                }
                .pickerStyle(.segmented)

                if demo.profile == .custom {
                    slider(
                        title: "Target Speed",
                        value: "\(Int(demo.customTargetKPH)) km/h",
                        binding: customTargetBinding,
                        range: 0...200,
                        step: 5
                    )

                    slider(
                        title: "Acceleration",
                        value: "\(Int(demo.customAcceleration)) km/h/s",
                        binding: customAccelerationBinding,
                        range: 1...30,
                        step: 1
                    )

                    slider(
                        title: "Duration",
                        value: "\(Int(demo.customDuration)) s",
                        binding: customDurationBinding,
                        range: 10...300,
                        step: 10
                    )

                    HStack {
                        Button(demo.isManualStillness ? "Resume Motion" : "Hold Still") {
                            demo.setManualStillness(!demo.isManualStillness)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if demo.isManualStillness {
                            Text("Target 0 km/h")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .frame(minHeight: AppTheme.Control.compact)
                }
            } header: {
                Label("Playback", systemImage: "play.speedometer")
            } footer: {
                Text("At 5× or 10× the simulated clock advances faster, while speed, distance and trip time remain physically consistent.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Accuracy")
                        Spacer()
                        Text("±\(Int(demo.accuracyMeters)) m")
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                    }

                    Slider(value: accuracyBinding, in: 3...120, step: 1) {
                        Text("GPS Accuracy")
                    } minimumValueLabel: {
                        Text("3")
                    } maximumValueLabel: {
                        Text("120")
                    }
                    .accessibilityValue("\(Int(demo.accuracyMeters)) meters")
                }

                Picker("Signal", selection: signalBinding) {
                    ForEach(DemoSignalMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(demo.signalMode.summary)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    demo.setSignalMode(.live)
                } label: {
                    Label("Restore GPS", systemImage: "location.fill")
                }
                .disabled(demo.signalMode == .live)
                .frame(minHeight: AppTheme.Control.compact)

                Text("Below 35 m the dashboard reports a ready fix; above it the reading is low accuracy. Five seconds without a fix turn the reading stale.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("GPS Conditions", systemImage: "antenna.radiowaves.left.and.right")
            }

            Section {
                LabeledContent("Speed", value: String(format: "%.0f km/h", demo.simulatedSpeedKPH))
                LabeledContent("Recorded Distance", value: formattedDistance)
                LabeledContent("Trip Time", value: formattedDuration)
                LabeledContent("Demo Clock", value: String(format: "%.0f s", demo.simulatedElapsed))
            } header: {
                Label("Live Readout", systemImage: "gauge.with.dots.needle.67percent")
            } footer: {
                Text("Distance and trip time come from TripRecorder through the normal trip session, not from the demo timeline.")
            }

            Section {
                sessionControls
            } header: {
                Label("Session", systemImage: "record.circle")
            } footer: {
                if !demo.isEnabled {
                    Text("Enable Demo Mode in Settings to start a simulated trip.")
                } else {
                    Text("Starting resets any previous session. Leaving Demo Mode ends the session and clears simulated data.")
                }
            }
        }
        .navigationTitle("Demo Controls")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .tint(AppTheme.Colors.accent)
        .sensoryFeedback(.impact(weight: .light), trigger: demo.isRunning)
        .sensoryFeedback(.impact(weight: .light), trigger: demo.isPaused)
    }

    @ViewBuilder
    private var sessionControls: some View {
        if demo.isRunning {
            Button {
                demo.pause()
            } label: {
                Label("Pause Simulation", systemImage: "pause.fill")
            }
            .frame(minHeight: AppTheme.Control.compact)

            Button {
                demo.stop()
            } label: {
                Label("Stop Simulation", systemImage: "stop.fill")
            }
            .frame(minHeight: AppTheme.Control.compact)
        } else if demo.isPaused {
            Button {
                demo.resume()
            } label: {
                Label("Resume Simulation", systemImage: "play.fill")
            }
            .frame(minHeight: AppTheme.Control.compact)

            Button {
                demo.stop()
            } label: {
                Label("Stop Simulation", systemImage: "stop.fill")
            }
            .frame(minHeight: AppTheme.Control.compact)
        } else {
            Button {
                demo.start()
            } label: {
                Label("Start Simulation", systemImage: "play.fill")
            }
            .disabled(!demo.isEnabled)
            .frame(minHeight: AppTheme.Control.compact)
        }

        if demo.hasSession {
            Button(role: .destructive) {
                demo.reset()
            } label: {
                Label("Reset Trip", systemImage: "arrow.counterclockwise")
            }
            .frame(minHeight: AppTheme.Control.compact)
        }
    }

    private func slider(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            Slider(value: binding, in: range, step: step) {
                Text(title)
            }
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%.1f×", rate)
    }

    private var formattedDistance: String {
        String(format: "%.2f km", tripSession.distanceMeters / 1_000)
    }

    private var formattedDuration: String {
        let seconds = max(0, Int(tripSession.elapsedSeconds))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private var profileBinding: Binding<DemoDriveProfile> {
        Binding(get: { demo.profile }, set: { demo.setProfile($0) })
    }

    private var rateBinding: Binding<Double> {
        Binding(get: { demo.rate }, set: { demo.setRate($0) })
    }

    private var accuracyBinding: Binding<Double> {
        Binding(get: { demo.accuracyMeters }, set: { demo.setAccuracy($0) })
    }

    private var signalBinding: Binding<DemoSignalMode> {
        Binding(get: { demo.signalMode }, set: { demo.setSignalMode($0) })
    }

    private var customTargetBinding: Binding<Double> {
        Binding(get: { demo.customTargetKPH }, set: { demo.setCustomTarget($0) })
    }

    private var customAccelerationBinding: Binding<Double> {
        Binding(get: { demo.customAcceleration }, set: { demo.setCustomAcceleration($0) })
    }

    private var customDurationBinding: Binding<Double> {
        Binding(get: { demo.customDuration }, set: { demo.setCustomDuration($0) })
    }
}
