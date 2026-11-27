import AppIntents
import SwiftUI

/// Describes one charging session in full, defaulting to the most recent one.
@AppIntent(.tool)
public struct GetChargeDetailsIntent: AppIntent, PredictableIntent {
    public static let title: LocalizedStringResource = "Get Charge Details"
    public static let description = IntentDescription(
        "Gets everything recorded about one Tesla charging session: where and when, Supercharger or AC, battery before and after, energy added and drawn from the charger, charging efficiency, range added, duration, and cost. Leave the session empty for the most recent charge, such as \"how much did my last charge cost?\".",
        searchKeywords: ["Tesla", "last charge", "charge cost", "Supercharger cost", "how much did charging cost", "kWh added"]
    )
    public static let isDiscoverable = true
    // Drive and charging history reveals addresses, including home.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public static var allowedExecutionTargets: IntentExecutionTargets { [.main, .appIntentsExtension] }

    @Parameter(
        title: "Vehicle",
        description: "The Tesla whose latest charge to describe when no session is given. Leave empty to use the car the user has selected in the app.",
        requestValueDialog: IntentDialog("Which vehicle?"),
        requestDisambiguationDialog: IntentDialog("Which vehicle?"),
        optionsProvider: SelectedVehicleOptionsProvider()
    )
    public var vehicle: VehicleEntity?

    @Parameter(
        title: "Charging Session",
        description: "The session to describe, such as one the user is looking at or one found with Get Charging History. Leave empty for the most recent charge.",
        requestValueDialog: IntentDialog("Which charging session?")
    )
    public var charge: ChargeSessionEntity?

    public init() {}

    public init(vehicle: VehicleEntity? = nil, charge: ChargeSessionEntity? = nil) {
        self.vehicle = vehicle
        self.charge = charge
    }

    public static var parameterSummary: some ParameterSummary {
        When(\.$charge, .hasAnyValue) {
            Summary("Get details for \(\.$charge)")
        } otherwise: {
            When(\.$vehicle, .hasAnyValue) {
                Summary("Get details for \(\.$vehicle)'s latest charge")
            } otherwise: {
                Summary("Get details for my car's latest charge")
            }
        }
    }

    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$vehicle)) { vehicle in
            DisplayRepresentation(
                title: vehicle.map {
                    LocalizedStringResource("Show \($0.name)'s latest charge", bundle: FleetKitLocalization.bundleDescription, comment: "Siri suggestion to inspect a named vehicle's latest charging session")
                } ?? LocalizedStringResource("Show my car's latest charge", bundle: FleetKitLocalization.bundleDescription, comment: "Siri suggestion to inspect the user's car's latest charging session")
            )
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<ChargeSessionEntity> & ShowsSnippetIntent & ProvidesDialog {
        let log = FleetIntentLog(Self.self, vehicle: vehicle)
        do {
            let service = FleetIntentService.make()
            let summary: ChargeSessionEntity
            let vehicleName: String

            if let charge {
                let vehicles = try await service.vehicles()
                guard let owner = vehicles.first(where: { $0.vin == charge.vin }) else {
                    throw FleetKitError.api(String(localized: "That charging session doesn't belong to a car on your current account.", bundle: .module, comment: "Error when a requested charging session is not on the signed-in account"))
                }
                vehicleName = owner.name
                summary = charge
            } else {
                let resolved = try await service.resolvedVehicle(vehicle?.id)
                vehicleName = resolved.name
                guard let latest = try await service.charges(vin: resolved.vin, limit: 1).first else {
                    throw FleetKitError.api(String(localized: "No charging sessions have been recorded for \(resolved.name) yet.", bundle: .module, comment: "Error when a vehicle has no charging history"))
                }
                summary = ChargeSessionEntity(info: latest, vehicleName: resolved.name)
            }

            let session = try await service.chargeDetails(summary)
            var spoken = session.spokenSummary(vehicleName: vehicleName)
            if let efficiency = session.chargingEfficiencyPercent, let drawn = session.energyDrawnKWH {
                let drawnText = FleetKitFormatting.energyKWH(drawn)
                let effText = FleetKitFormatting.percent(efficiency)
                spoken += " " + String(localized: "It drew \(drawnText) from the charger, \(effText) efficient.", bundle: .module, comment: "Spoken detail about energy drawn from charger and charging efficiency")
            }
            if session.cost == nil {
                spoken += " " + String(localized: "No cost was recorded.", bundle: .module, comment: "Spoken note when a charging session has no recorded cost")
            }
            log.success("described charge \(session.id) for \(vehicleName)")
            return .result(
                value: session,
                dialog: IntentDialog(stringLiteral: spoken),
                snippetIntent: ChargeSessionSnippetIntent(
                    sessions: [session],
                    vehicleName: vehicleName,
                    sessionKey: "charge-detail"
                )
            )
        } catch {
            throw log.failure(error)
        }
    }
}

/// Interactive Siri snippet card for a charging session with an embedded Apple Maps
/// charger pin, Satellite/Standard toggle, battery-added fill bar, and session stepper.
public struct ChargeSessionSnippetView: View {
    public let session: ChargeSessionEntity
    public let allSessions: [ChargeSessionEntity]
    public let selectedIndex: Int
    public let sessionKey: String
    public let vehicleName: String
    public let mapData: SiriRenderedMapData?

    public init(
        session: ChargeSessionEntity,
        allSessions: [ChargeSessionEntity]? = nil,
        selectedIndex: Int = 0,
        sessionKey: String = "charge-latest",
        vehicleName: String? = nil,
        mapData: SiriRenderedMapData? = nil
    ) {
        self.session = session
        self.allSessions = allSessions ?? [session]
        self.selectedIndex = selectedIndex
        self.sessionKey = sessionKey
        self.vehicleName = vehicleName ?? String(localized: "My Car", bundle: .module, comment: "Default fallback name for a vehicle")
        self.mapData = mapData
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            chargerMapCard

            batteryAddedCard

            metricsRow

            footerBar
        }
        .padding(14)
        .appEntityIdentifier(EntityIdentifier(for: ChargeSessionEntity.self, identifier: session.id))
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Label(
                session.chargerKindText,
                systemImage: session.isSupercharger ? "bolt.fill" : "ev.charger.fill"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(session.isSupercharger ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.green))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                (session.isSupercharger ? Color.red.opacity(0.14) : Color.green.opacity(0.14)),
                in: Capsule()
            )

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if allSessions.count > 1 {
                HStack(spacing: 4) {
                    Button(
                        intent: SelectSnippetItemIntent(
                            sessionKey: sessionKey,
                            targetIndex: max(0, selectedIndex - 1),
                            cardType: "charge"
                        )
                    ) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .disabled(selectedIndex <= 0)
                    .accessibilityLabel(Text("Previous charging session", bundle: .module, comment: "Accessibility label for previous charging session button"))

                    Text(verbatim: "\(selectedIndex + 1)/\(allSessions.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()

                    Button(
                        intent: SelectSnippetItemIntent(
                            sessionKey: sessionKey,
                            targetIndex: min(allSessions.count - 1, selectedIndex + 1),
                            cardType: "charge"
                        )
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .disabled(selectedIndex >= allSessions.count - 1)
                    .accessibilityLabel(Text("Next charging session", bundle: .module, comment: "Accessibility label for next charging session button"))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private var chargerMapCard: some View {
        let style = mapData?.style ?? SiriSnippetStateStore.shared.mapStyle(for: "charge")
        return ZStack(alignment: .topTrailing) {
            Group {
                if let image = mapData?.swiftUIImage {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    SiriVectorRouteFallbackView(points: fallbackPoints)
                }
            }
            .frame(height: 118)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Button(intent: ToggleSnippetMapStyleIntent(scope: "charge")) {
                Label(style.badgeLabel, systemImage: style.badgeIcon)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(8)

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.isSupercharger ? .red : .green)
                    Text(
                        session.location
                            ?? String(localized: "\(vehicleName) Charger", bundle: .module, comment: "Fallback charging location title")
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.75)
        )
    }

    private var batteryAddedCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.energyText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let miles = session.milesAdded {
                    Text(verbatim: "· +\(FleetKitFormatting.distance(miles: miles))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                if let start = session.startingBatteryPercent, let end = session.endingBatteryPercent {
                    HStack(spacing: 3) {
                        Text(FleetKitFormatting.percent(start))
                        Image(systemName: "arrow.forward")
                            .font(.caption2.weight(.semibold))
                        Text(FleetKitFormatting.percent(end))
                    }
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                }
            }

            if let start = session.startingBatteryPercent, let end = session.endingBatteryPercent, end >= start {
                let startFrac = min(max(Double(start) / 100.0, 0), 1)
                let endFrac = min(max(Double(end) / 100.0, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    FractionalCapsuleBar(fraction: startFrac, minimumWidth: 4)
                        .fill(Color.secondary.opacity(0.32))

                    FractionalCapsuleBar(startFraction: startFrac, endFraction: endFrac, minimumWidth: 6)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.8), .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .flipsForRightToLeftLayoutDirection(true)
                .frame(height: 9)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metricPill(
                icon: "clock",
                label: LocalizedStringResource("Duration", bundle: FleetKitLocalization.bundleDescription, comment: "Charging session duration metric label"),
                value: session.durationMinutes.map { FleetKitFormatting.durationMinutes($0) } ?? "—"
            )
            metricPill(
                icon: "creditcard",
                label: LocalizedStringResource("Cost", bundle: FleetKitLocalization.bundleDescription, comment: "Charging session cost metric label"),
                value: session.formattedCost ?? "—"
            )
            metricPill(
                icon: "gauge.with.dots.needle.67percent",
                label: LocalizedStringResource("Efficiency", bundle: FleetKitLocalization.bundleDescription, comment: "Charging session efficiency metric label"),
                value: session.chargingEfficiencyPercent.map { FleetKitFormatting.percent($0) } ?? "—"
            )
        }
    }

    private func metricPill(icon: String, label: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var footerBar: some View {
        if let url = session.appleMapsLocationURL {
            HStack {
                Text(vehicleName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: url) {
                    Label {
                        Text("Apple Maps", bundle: .module, comment: "Button to open charging location in Apple Maps")
                    } icon: {
                        Image(systemName: "map.fill")
                    }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private var fallbackPoints: [FleetDriveRoutePoint] {
        if let pts = mapData?.points, !pts.isEmpty {
            return pts
        }
        if let lat = session.latitude, let lon = session.longitude {
            return [FleetDriveRoutePoint(latitude: lat, longitude: lon)]
        }
        return [FleetDriveRoutePoint(latitude: 37.3947, longitude: -122.1503)]
    }
}

public struct EmptyChargeSnippetView: View {
    public let vehicleName: String

    public init(vehicleName: String) {
        self.vehicleName = vehicleName
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ev.charger.slash.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Charging Sessions Found", bundle: .module, comment: "Empty state title when no charging sessions match")
                    .font(.subheadline.weight(.semibold))
                Text("No matching charges recorded for \(vehicleName).", bundle: .module, comment: "Empty state description when no charging sessions match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

