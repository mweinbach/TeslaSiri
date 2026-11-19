import AppIntents
import FleetKit
import SwiftUI

/// Software card on the Vehicle tab: installed version, update status and actions,
/// and drill-downs into the release notes.
struct SoftwareUpdateCard: View {
    let store: FleetDataStore
    let update: FleetSoftwareUpdate
    let vin: String?

    @State private var pendingAction: SoftwareUpdateMutationAction?

    var body: some View {
        DashboardCard("Software", systemImage: hasPendingOrAvailableUpdate ? "arrow.down.app.fill" : "checkmark.seal", tint: hasPendingOrAvailableUpdate ? .orange : .secondary) {
            StatusBadge(
                statusText,
                systemImage: hasPendingOrAvailableUpdate ? "arrow.down.circle.fill" : "checkmark.seal.fill",
                tint: hasPendingOrAvailableUpdate ? .orange : .green
            )
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.currentVersion ?? "--")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .textSelection(.enabled)
                        Text("Installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 12)

                    if let availableVersion = normalizedAvailableVersion {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(availableVersion)
                                .font(.headline)
                                .foregroundStyle(.orange)
                                .monospacedDigit()
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let downloadPercent = update.downloadPercent, hasPendingOrAvailableUpdate {
                    SoftwareProgressRow(label: "Downloaded", percent: downloadPercent)
                }

                if let installPercent = update.installPercent, installPercent > 0 {
                    SoftwareProgressRow(label: "Installing", percent: installPercent)
                }

                if let scheduledStartDate = update.scheduledStartDate {
                    LabeledContent("Scheduled") {
                        Text(scheduledStartDate.formatted(date: .abbreviated, time: .shortened))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }

                if canInstallUpdate || canCancelUpdate {
                    HStack(spacing: 10) {
                        if canInstallUpdate {
                            Button("Install Now", systemImage: "arrow.down.circle.fill") {
                                pendingAction = .installNow
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.orange)
                        }

                        if canCancelUpdate {
                            Button("Cancel Update", systemImage: "xmark") {
                                pendingAction = .cancel
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .disabled(store.isLoadingSoftware || store.isMutatingSoftware)
                }

                if !store.softwareActionMessage.isEmpty,
                   store.softwareActionMessage != "Not run" {
                    Text(store.softwareActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !update.releaseNotes.isEmpty {
                    releaseNotes
                }
            }
        }
        .appEntityIdentifier(softwareEntityIdentifier)
        .softwareMutationDialog(
            pendingAction: $pendingAction,
            onInstall: installSoftwareUpdate,
            onCancel: cancelSoftwareUpdate
        )
    }

    private var releaseNotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            Text("Release Notes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(Array(update.releaseNotes.prefix(3))) { note in
                NavigationLink {
                    SoftwareReleaseNoteDetailView(note: note, version: notesVersion)
                } label: {
                    HStack(spacing: 10) {
                        SoftwareReleaseNoteSummaryLabel(note: note, vin: vin, version: notesVersion)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if update.releaseNotes.count > 3 {
                NavigationLink {
                    SoftwareReleaseNotesListView(notes: update.releaseNotes, vin: vin, version: notesVersion)
                } label: {
                    DashboardCardLinkLabel(
                        title: "All Release Notes",
                        systemImage: "doc.text",
                        detail: "\(update.releaseNotes.count)"
                    )
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesVersion: String? {
        update.availableVersion ?? update.currentVersion
    }

    private var normalizedAvailableVersion: String? {
        guard let raw = update.availableVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != update.currentVersion else {
            return nil
        }
        return raw
    }

    private var hasPendingOrAvailableUpdate: Bool {
        update.updateAvailable || normalizedAvailableVersion != nil || canCancelUpdate
    }

    private var statusText: String {
        if update.updateAvailable || normalizedAvailableVersion != nil {
            return "Update Available"
        }
        guard let raw = update.status, !raw.isEmpty else {
            return "Up to Date"
        }
        let lowered = raw.lowercased()
        if lowered == "current" || lowered == "up_to_date" || lowered == "up to date" {
            return "Up to Date"
        }
        return humanizedStatus(raw)
    }

    private var softwareEntityIdentifier: EntityIdentifier? {
        guard let vin, !vin.isEmpty else { return nil }
        return EntityIdentifier(for: SoftwareUpdateEntity.self, identifier: SoftwareUpdateEntity.entityID(forVIN: vin))
    }

    private var canInstallUpdate: Bool { update.installable && store.selectedVehicle?.allowsVehicleControls == true }

    private var canCancelUpdate: Bool {
        guard store.selectedVehicle?.allowsVehicleControls == true,
              store.capabilities?.software["cancel"] != .bool(false) else { return false }
        return update.scheduledStartTimeMS != nil
            || update.warningTimeRemainingMS != nil
            || update.status?.localizedCaseInsensitiveContains("scheduled") == true
            || update.status?.localizedCaseInsensitiveContains("pending") == true
    }

    private func installSoftwareUpdate() async {
        let vehicle = store.selectedVehicle
        guard await store.installSelectedVehicleSoftwareUpdate(offsetSec: 0) else { return }
        await FleetIntentDonations.donateSoftwareInstall(for: vehicle)
    }

    private func cancelSoftwareUpdate() async {
        let vehicle = store.selectedVehicle
        guard await store.cancelSelectedVehicleSoftwareUpdate() else { return }
        await FleetIntentDonations.donateSoftwareCancel(for: vehicle)
    }
}

enum SoftwareUpdateMutationAction: String, Identifiable {
    case cancel
    case installNow

    var id: String { rawValue }
}

private extension View {
    func softwareMutationDialog(
        pendingAction: Binding<SoftwareUpdateMutationAction?>,
        onInstall: @escaping () async -> Void,
        onCancel: @escaping () async -> Void
    ) -> some View {
        confirmationDialog("Software Update", item: pendingAction) { action in
            switch action {
            case .installNow:
                Button("Install Now", role: .destructive) {
                    Task { await onInstall() }
                }
            case .cancel:
                Button("Cancel Update") {
                    Task { await onCancel() }
                }
            }
        } message: { action in
            switch action {
            case .installNow:
                Text("Schedule the available software update to install as soon as the vehicle accepts the command.")
            case .cancel:
                Text("Cancel the pending software update countdown for this vehicle.")
            }
        }
    }
}

private struct SoftwareProgressRow: View {
    let label: String
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedNumber(percent, fractionLength: 0, suffix: "%"))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)

            ProgressView(value: max(0, min(percent / 100, 1)))
                .tint(.orange)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SoftwareReleaseNoteSummaryLabel: View {
    let note: FleetSoftwareReleaseNote
    let vin: String?
    let version: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if let subtitle = note.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .appEntityIdentifier(releaseNoteEntityIdentifier)
    }

    private var releaseNoteEntityIdentifier: EntityIdentifier? {
        guard let vin, !vin.isEmpty else { return nil }
        let noteID = note.title + (note.subtitle ?? "")
        return EntityIdentifier(
            for: ReleaseNoteEntity.self,
            identifier: ReleaseNoteEntity.entityID(forVIN: vin, version: version, noteID: noteID)
        )
    }
}

private struct SoftwareReleaseNotesListView: View {
    let notes: [FleetSoftwareReleaseNote]
    let vin: String?
    let version: String?

    var body: some View {
        List(notes) { note in
            NavigationLink {
                SoftwareReleaseNoteDetailView(note: note, version: version)
            } label: {
                SoftwareReleaseNoteSummaryLabel(note: note, vin: vin, version: version)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppScreenBackground())
        .navigationTitle("Release Notes")
        .navigationSubtitle(version ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SoftwareReleaseNoteDetailView: View {
    let note: FleetSoftwareReleaseNote
    let version: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let version, !version.isEmpty {
                    Text("Version \(version)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(note.title)
                    .font(.title2.weight(.bold))

                if let subtitle = note.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let description = note.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: AppTheme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppScreenBackground())
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
