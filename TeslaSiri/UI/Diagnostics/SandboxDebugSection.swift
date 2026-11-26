import FleetKit
import SwiftUI

struct SandboxDebugSection: View {
    let mode: FleetSandboxMode
    let preset: FleetDemoPreset
    let demoState: FleetDemoVehicleState
    let commandLog: [FleetSimulatedCommandEntry]
    var verificationRunner: DemoSiriVerificationRunner?
    let onSelectMode: (FleetSandboxMode) -> Void
    let onSelectPreset: (FleetDemoPreset) -> Void
    let onResetPreset: () -> Void
    let onRefreshLog: () -> Void
    let onClearLog: () -> Void
    var onRunSiriVerification: () -> Void = {}

    private var modeBinding: Binding<FleetSandboxMode> {
        Binding(
            get: { mode },
            set: { onSelectMode($0) }
        )
    }

    private var presetBinding: Binding<FleetDemoPreset> {
        Binding(
            get: { preset },
            set: { onSelectPreset($0) }
        )
    }

    var body: some View {
        DashboardCard("Siri & Command Sandbox", systemImage: "checkmark.shield", tint: badgeTint) {
            StatusBadge(
                badgeText,
                systemImage: badgeSymbol,
                tint: badgeTint
            )
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Sandbox Mode", selection: modeBinding) {
                    ForEach(FleetSandboxMode.allCases) { candidate in
                        Text(candidate.shortTitle)
                            .tag(candidate)
                    }
                }
                .pickerStyle(.segmented)

                Text(mode.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if mode == .demoVehicle {
                    Divider()
                    demoScenarioControls
                }

                if let verificationRunner, mode == .demoVehicle || !verificationRunner.results.isEmpty {
                    Divider()
                    verificationSection(verificationRunner)
                }

                if mode != .live || !commandLog.isEmpty {
                    Divider()
                    simulatedCommandLogSection
                }
            }
        }
    }

    private var badgeText: String {
        switch mode {
        case .live:
            String(localized: "Live", comment: "Sandbox mode badge: connected to live vehicle")
        case .dryRun:
            String(localized: "Dry-Run", comment: "Sandbox mode badge: dry-run simulation")
        case .demoVehicle:
            String(localized: "Demo Car", comment: "Sandbox mode badge: simulated demo vehicle")
        }
    }

    private var badgeSymbol: String {
        switch mode {
        case .live:
            "antenna.radiowaves.left.and.right"
        case .dryRun:
            "shield.lefthalf.filled"
        case .demoVehicle:
            "sparkles"
        }
    }

    private var badgeTint: Color {
        switch mode {
        case .live:
            .secondary
        case .dryRun:
            AppTheme.alertAmber
        case .demoVehicle:
            AppTheme.accent
        }
    }

    private var demoScenarioControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticGroupHeader(String(localized: "Demo car scenario", comment: "Section header for selecting a simulated demo vehicle scenario"))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    scenarioPicker
                    Spacer(minLength: 8)
                    resetScenarioButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    scenarioPicker
                    resetScenarioButton
                }
            }

            Text(preset.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                SandboxStateSummaryRow(
                    label: "Climate",
                    value: demoClimateSummary
                )
                SandboxStateSummaryRow(
                    label: "Security",
                    value: demoSecuritySummary
                )
                SandboxStateSummaryRow(
                    label: "Battery",
                    value: String(
                        localized: "\(formattedPercent(demoState.batteryLevel)) · \(formattedPercent(demoState.chargeLimitSOC)) limit · \(humanizedStatus(demoState.chargingState))",
                        comment: "Demo car battery summary showing charge level, charge limit, and charging state"
                    )
                )
                if let destination = demoState.lastNavigationDestination, !destination.isEmpty {
                    SandboxStateSummaryRow(
                        label: "Sent destination",
                        value: destination
                    )
                }
            }
            .padding(12)
            .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var scenarioPicker: some View {
        Picker("Scenario", selection: presetBinding) {
            ForEach(FleetDemoPreset.allCases) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.primary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var resetScenarioButton: some View {
        Button("Reset", systemImage: "arrow.counterclockwise") {
            onResetPreset()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var demoClimateSummary: String {
        let target = formattedTemperature(demoState.targetTempF, inFahrenheit: true)
        let inside = formattedTemperature(demoState.insideTempF, inFahrenheit: true)
        let outside = formattedTemperature(demoState.outsideTempF, inFahrenheit: true)
        var parts = [
            demoState.hvacOn
                ? String(localized: "On", comment: "Climate status in demo car summary: on")
                : String(localized: "Off", comment: "Climate status in demo car summary: off"),
            String(localized: "Target \(target)", comment: "Demo car target cabin temperature"),
            String(localized: "In \(inside) / Out \(outside)", comment: "Demo car inside and outside temperatures")
        ]
        if demoState.defrostOn {
            parts.append(String(localized: "Defrost", comment: "Demo car climate feature: max defrost"))
        }
        if demoState.steeringWheelHeaterOn {
            parts.append(String(localized: "Wheel heat", comment: "Demo car climate feature: heated steering wheel"))
        }
        if let driverHeat = demoState.seatHeaterLevels["Driver"], driverHeat > 0 {
            parts.append(String(localized: "Driver seat \(driverHeat)", comment: "Demo car driver seat heater level"))
        }
        if demoState.petModeOn {
            parts.append(String(localized: "Dog Mode", comment: "Tesla Dog Mode climate feature"))
        }
        return parts.joined(separator: " · ")
    }

    private var demoSecuritySummary: String {
        var parts = [
            demoState.locked
                ? String(localized: "Locked", comment: "Demo car security summary: locked")
                : String(localized: "Unlocked", comment: "Demo car security summary: unlocked"),
            demoState.sentryModeOn
                ? String(localized: "Sentry On", comment: "Demo car security summary: Sentry Mode enabled")
                : String(localized: "Sentry Off", comment: "Demo car security summary: Sentry Mode disabled")
        ]
        let closures = demoState.openClosureNames
        if !closures.isEmpty {
            let list = closures.formatted(.list(type: .and))
            parts.append(String(localized: "Open: \(list)", comment: "Demo car security summary list of open doors, windows, or trunks"))
        }
        return parts.joined(separator: " · ")
    }

    private func verificationSection(_ runner: DemoSiriVerificationRunner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                DiagnosticGroupHeader(String(localized: "Siri skills & tools check", comment: "Section header for running end-to-end Siri tool verification on the demo car"))
                Spacer()
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Run All", systemImage: "play.fill") {
                        onRunSiriVerification()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if runner.results.isEmpty && !runner.isRunning {
                Text("Runs all 5 bundled Siri AI Skills, all 38 Siri tools, App Shortcuts, and Spotlight EntityQueries end-to-end against the Demo Car.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    StatusBadge(
                        String(localized: "\(runner.passedCount)/\(runner.results.count) passed", comment: "Siri verification badge showing passed checks out of total checks"),
                        systemImage: runner.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        tint: runner.failedCount == 0 ? .green : .red
                    )
                    if runner.totalConfirmationsRecorded > 0 {
                        Text("\(runner.totalConfirmationsRecorded) safety gates checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(runner.results) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(step.passed ? Color.green : Color.red)
                                .font(.subheadline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.caption.weight(.semibold))
                                Text(step.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Text(Duration.milliseconds(step.durationMS).formatted(.units(allowed: [.milliseconds], width: .narrow)))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var simulatedCommandLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                DiagnosticGroupHeader(String(localized: "Intercepted commands (\(commandLog.count))", comment: "Section header for intercepted simulated commands with count"))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    onRefreshLog()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)

                if !commandLog.isEmpty {
                    Button("Clear Log", systemImage: "trash", role: .destructive) {
                        onClearLog()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            if commandLog.isEmpty {
                Text("No simulated commands yet. Ask Siri to \"warm up my car\" or \"cool down my car to 68\" and the intercepted tool calls will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(commandLog.prefix(12)) { entry in
                        SimulatedCommandRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct SandboxStateSummaryRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SimulatedCommandRow: View {
    let entry: FleetSimulatedCommandEntry

    private var localizedSource: String {
        if entry.source == "App" {
            return String(localized: "App", comment: "Command log source badge for actions triggered from inside the app")
        }
        return entry.source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.humanizedAction)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Text(localizedSource)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.source == "Siri" ? .blue : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (entry.source == "Siri" ? Color.blue : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.action)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let params = entry.parametersSummary, !params.isEmpty {
                    Text("· \(params)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.insetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
