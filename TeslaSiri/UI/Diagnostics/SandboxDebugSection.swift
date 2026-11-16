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
        CardContainer(title: "Siri & Command Sandbox", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    StatusBadge(
                        badgeText,
                        systemImage: badgeSymbol,
                        tint: badgeTint
                    )
                    Spacer(minLength: 0)
                }

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
            "Live Car Commands Enabled"
        case .dryRun:
            "Dry-Run · Car Protected"
        case .demoVehicle:
            "Demo Car · Car Protected"
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
            .orange
        case .demoVehicle:
            .blue
        }
    }

    private var demoScenarioControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiagnosticGroupHeader("Demo car scenario")

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
                    value: "\(Int(demoState.batteryLevel.rounded()))% · \(Int(demoState.chargeLimitSOC.rounded()))% limit · \(demoState.chargingState)"
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
    }

    private var resetScenarioButton: some View {
        Button("Reset Scenario", systemImage: "arrow.counterclockwise") {
            onResetPreset()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var demoClimateSummary: String {
        var parts = [
            demoState.hvacOn ? "On" : "Off",
            "Target \(Int(demoState.targetTempF.rounded()))°F",
            "In \(Int(demoState.insideTempF.rounded()))°F / Out \(Int(demoState.outsideTempF.rounded()))°F"
        ]
        if demoState.defrostOn {
            parts.append("Defrost")
        }
        if demoState.steeringWheelHeaterOn {
            parts.append("Wheel heat")
        }
        if let driverHeat = demoState.seatHeaterLevels["Driver"], driverHeat > 0 {
            parts.append("Driver seat \(driverHeat)")
        }
        if demoState.petModeOn {
            parts.append("Dog Mode")
        }
        return parts.joined(separator: " · ")
    }

    private var demoSecuritySummary: String {
        var parts = [
            demoState.locked ? "Locked" : "Unlocked",
            demoState.sentryModeOn ? "Sentry On" : "Sentry Off"
        ]
        let closures = demoState.openClosureNames
        if !closures.isEmpty {
            parts.append("Open: \(closures.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    private func verificationSection(_ runner: DemoSiriVerificationRunner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                DiagnosticGroupHeader("Siri skills & tools check")
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
                        "\(runner.passedCount)/\(runner.results.count) passed",
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
                            Text("\(step.durationMS)ms")
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
                DiagnosticGroupHeader("Intercepted commands (\(commandLog.count))")
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
    let label: String
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.humanizedAction)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Text(entry.source)
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
