---
name: siri-ai-tool-design
description: Designs, implements, extends, and validates iOS 27.3 Siri AI tools (@AppIntent(.tool)), generable composite entities (@AppEntity(.generable)), SyncableEntity/IndexedEntity @Property models, onscreen/notification EntityIdentifier grounding, safety confirmation dialogs, and bundled Siri AI workflow skills (SKILL.md) in TeslaSiri and FleetKit. Use whenever adding or modifying App Intents, vehicle telemetry/control tools, Siri AI workflows, or entity grounding in TeslaSiri.
---

# TeslaSiri — Siri AI Tool & Skill Design Guide

Use this skill whenever adding, updating, or reviewing Siri AI / Apple Intelligence App Intents, entities, or workflow skills in `TeslaSiri` and `FleetKit`.

## 1. Architecture & Target Boundaries

- Domain intents, entities, queries, and snippet views live in `FleetKit/Sources/FleetKit/` and are exported through `FleetKitPackage: AppIntentsPackage`. The app ships Siri workflows from `TeslaSiri/Skills.skillsbundle/Skills/`.
- **`TeslaSiriAppIntentsExtension`** links `FleetKit` statically (empty `extension TeslaSiriAppIntentsExtension: AppIntentsPackage {}` without `includedPackages`, avoiding the static-link duplicate metadata warning); **`TeslaSiriApp`** also links `FleetKit` so Siri can run tools in-extension without launching the main UI.
- **Deployment Target**: `@AppIntent(.tool)` and `@AppEntity(.generable)` require **iOS 27.3 / macOS 27.3** (`FleetKit/Package.swift` and `IPHONEOS_DEPLOYMENT_TARGET = 27.3`).
- **`TeslaSiriShortcuts` (`AppShortcutsProvider`) stays in the app target** (`TeslaSiri/AppIntents/TeslaSiriShortcuts.swift`) and **must never exceed 10 `AppShortcut` entries** (Apple's hard compile-time limit). Exposing new intents to Siri AI via `@AppIntent(.tool)` does **not** consume an `AppShortcut` slot.
- **Xcode MCP note**: When creating brand-new `.swift` files inside the local `FleetKit` SwiftPM package, Xcode 27.3's `XcodeWrite` may fail with `Invalid directory insertion mode 'folders'` on SwiftPM targets; create new package files cleanly on disk and use `XcodeUpdate` for editing existing files.

## 2. `@AppIntent(.tool)` Authoring Rules (Xcode 27.3)

1. **Macro & Protocol Conformance**:
   - Annotate custom read, search, analytics, and mutation intents with `@AppIntent(.tool)` **and** keep explicit `: AppIntent` conformance on the struct (e.g., `public struct LockVehicleIntent: AppIntent, PredictableIntent`, or `public struct InstallSoftwareUpdateIntent: AppIntent, LongRunningIntent, PredictableIntent`).
   - **Never** add `.tool` to `@AppIntent(schema: .system.open)` (`OpenEntityIntents.swift`) or `@AppIntent(schema: .system.searchInApp)` (`SearchFleetIntent.swift`) — system schema macros supply their own traits.
2. **No Unwrapped Stored Properties on `@AppIntent(.tool)` Structs**:
   - `@AppIntent(.tool)` is a `@attached(memberAttribute)` macro that attaches `@Parameter` to **every un-annotated stored property** on the struct.
   - Never add helper stored properties (`let service`, caches, loggers) on an intent struct. Resolve `let service = FleetIntentService.make()` inside `perform()`, using `FleetIntentService.$testingOverride` for unit test injection.
3. **Inline String Literals for Metadata**:
   - `appintentsmetadataprocessor` requires inline string literals on `title`, `IntentDescription("...")`, and every `@Parameter(title: "...", description: "...", requestValueDialog: IntentDialog("..."))`. Never pass static constants into `@Parameter`.
4. **LLM-Oriented Descriptions & Spoken Readout**:
   - State **what** the tool reads or mutates, **units & valid bounds** (`50...100` percent; a cabin temperature exactly as the user said it, 59–82.4 °F or 15–28 °C, which the tool converts), **side effects / confirmation behavior**, and keep the Siri tool surface lean (20 tools) and each description under 60 words (analyzer rule SMA204): use `ControlCarIntent` as the primary car control tool, `UnlockOrOpenCarIntent` for anything that opens the car or lowers its security, `LocateCarIntent` for where the car is, and dedicated control tools only for `SetCabinTemperatureIntent`, `SetSeatClimateIntent` ("Set Seat Climate"), `SendNavigationIntent`, `InstallSoftwareUpdateIntent`, and `CancelSoftwareUpdateIntent`. Single-action control intents stay plain `AppIntent`s for Shortcuts, App Shortcuts, and snippet buttons.
   - Ensure readouts (`ProvidesDialog`) speak actual user-facing content (such as `ReleaseNoteEntity.spokenDigest(...)`, `DriveEntity.spokenSummary(vehicleName:)`, or stats summaries) rather than bare record counts.
5. **Default Vehicle Resolution**:
   - Every vehicle-scoped tool takes `public var vehicle: VehicleEntity?` (`optionsProvider: SelectedVehicleOptionsProvider()`) and resolves `try await service.resolvedVehicle(vehicle?.id)` so omitting `vehicle` targets the user's selected car while onscreen/notification `VehicleEntity` context binds automatically.
   - Use **List Cars** for vehicle or capability discovery. Pass the returned `VehicleEntity` through the whole workflow when the user chooses a named car. Commands for the default car can go directly to **Control Car**. An explicitly selected vehicle that disappears must fail before any command is sent.
6. **Structured Return Values**:
   - Read tools return typed `AppEntity` / `[AppEntity]` / `TransientAppEntity` (`VehicleStatusEntity`, `DriveEntity`, `ChargeSessionEntity`, `DrivingStatsEntity`, `ChargingStatsEntity`, `BatteryHealthEntity`, `SoftwareUpdateEntity`, `ReleaseNoteEntity`) or scalar values (`Int`, `Double`) alongside `ProvidesDialog` (and `@MainActor` `ShowsSnippetView` where appropriate).
   - Every mutation tool returns `ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog` so Siri AI receives machine-readable confirmation (`vehicleName`, `vin`, `action`, `succeeded`, `appliedValue`, `summary`, `executedAt`) for multi-step reasoning.
7. **Logging Convention**:
   - Every `perform()` must start with `let log = FleetIntentLog(Self.self, vehicle: vehicle)` and wrap its body in `do { ... log.success(...) } catch { throw log.failure(error) }`. Never log raw tokens or full VINs.
   - Siri reads the error a tool throws, but only when it conforms to `CustomLocalizedStringResourceConvertible`. `log.failure(_:)` converts raw `URLError`/`DecodingError` with `FleetKitError.readableBySiri`, so always throw its return value. Throw `FleetKitError.api("…")` with a sentence that says what went wrong and what would fix it.

## 3. Confirmation & Safety Policy

Always call `try await requestConfirmation(dialog:)` inside `perform()` before executing security-sensitive, physical-access, or disruptive vehicle commands:

| Requires `requestConfirmation` | Executes Directly (Reversible / Low-Risk) |
| --- | --- |
| `UnlockVehicleIntent` | `LockVehicleIntent` |
| `OpenTrunkIntent` (rear trunk or frunk), Shortcuts-only `OpenFrunkIntent` | `StartClimateIntent`, `StopClimateIntent`, `SetCabinTemperatureIntent`, `ConfigureCabinClimateIntent` (except disabling Dog Mode) |
| `CloseWindowsIntent`, `ControlCarIntent` (`closeTrunk: true`) | `VentWindowsIntent`, `SetMaxDefrostIntent`, `SetBioweaponModeIntent`, `SetPetModeIntent(on: true)` |
| `SetChargePortIntent(action: .open)` | `SetChargePortIntent(action: .close)`, `StartChargingIntent` |
| `StopChargingIntent`, `SetChargeLimitIntent` | `SetSentryModeIntent(on: true)` |
| `SetSentryModeIntent(on: false)`, `SetPetModeIntent(on: false)` | `FlashLightsIntent`, `SendNavigationIntent`, `SetSeatClimateIntent`, `SetSteeringWheelHeaterIntent` |
| | `HonkHornIntent` and all read-only telemetry, drive search/details, release notes, and driving/charging/battery stats tools |
| `InstallSoftwareUpdateIntent`, `CancelSoftwareUpdateIntent` | |

`ControlCarIntent` and `UnlockOrOpenCarIntent` validate all requested changes, collect the actions in the confirmation column into a single prompt, and obtain that confirmation before dispatching the first command (`LongRunningIntent.runCarControl`). Keep their action policy aligned with the corresponding single-action tools.

### Authentication (Lock Screen) policy

Confirmation is not authentication: `requestConfirmation` on a locked iPhone is only a spoken "yes". `authenticationPolicy` is static per intent and defaults to `.alwaysAllowed`, which runs while the device is locked.

- `ControlCarIntent` stays `.alwaysAllowed` so "warm up my car" works hands-free. It therefore must not unlock doors, open the trunk, frunk, or charge port, or turn Sentry Mode off. Those live in `UnlockOrOpenCarIntent` (`.requiresAuthentication`). `CarControlSettings` rejects `locked: false` and `sentryOn: false` with an error that names the Unlock or Open Car tool, so Siri re-routes.
- Where the car is, and where it has been, require authentication: `LocateCarIntent`, the drive and charging history tools, and the `DriveEntity` / `ChargeSessionEntity` types. `GetVehicleInfoIntent` and `GetVehicleStatusIntent` build `VehicleStatusEntity(…, includesLocation: false)` and never geocode.
- A property-level `authenticationPolicy` only gates answers Siri composes from the entity. If a tool's own dialog or snippet would say or show the value, gate the intent.
- A `SnippetIntent` must not decide what to show from the contents of an entity parameter: the system can fetch the entity again from its query, which may return more than the presenting intent put in. Pass a plain value instead, as `VehicleStatusSnippetIntent.showsLocation` does for the map card.
- When adding a capability, decide which side of this line it falls on before choosing the tool it joins.

For several requested changes to one car, pass the supported fields together in `CarControlSettings`. The app orders the operations, including starting HVAC once before setting a temperature. After a partial failure, report the accepted steps and the first unconfirmed operation. Resume only on a new user request, using the outstanding changes. Use the specialist tools for software updates and seat cooling.

## 4. Entities: `IndexedEntity`, `SyncableEntity`, `@Property`, and `@AppEntity(.generable)`

1. **Server-Backed Entities (`IndexedEntity` + `SyncableEntity`)**:
   - `VehicleEntity`, `VehicleStatusEntity`, `DriveEntity`, `ChargeSessionEntity`, `SoftwareUpdateEntity`, and `ReleaseNoteEntity` conform to both `IndexedEntity` and `SyncableEntity` so Siri AI can find them in Spotlight without launching the app and inspect every `@Property(title: "...")` field. For tool intents Siri finds candidates only through Spotlight (`IndexedEntity`) or `EnumerableEntityQuery` (`VehicleEntityQuery`) and resolves them with `entities(for:)`; it does not call `EntityStringQuery.entities(matching:)` or `suggestedEntities()`, which the queries keep for the Shortcuts picker. `entities(for:)` must therefore resolve every identifier a tool can return: `DriveEntityQuery` pages back through `FleetIntentService.driveHistory` for drives older than the newest page.
   - `FleetSpotlightIndexer` keeps the newest 500 drives and 200 charging sessions per car indexed, the same depth `entities(for:)` can resolve, so prefer letting Siri find a drive or charge in Spotlight over adding search parameters to a tool.
   - Use an `AppEnum` for a property with a fixed set of values (`VehicleChargingState`, `SoftwareUpdateStatus`). When the provider can report values outside the cases, keep its wording in a plain stored property (`reportedChargingState`, `reportedStatus`) for display and leave the enum property `nil`.
   - `DriveEntity` and `ChargeSessionEntity` carry `vehicleName`; pass the roster name wherever one is created.
   - Keep `public let id: String` unwrapped; declare `@Property(title: "...", description: "...") public var ...` on every model property (iOS 27.3 adds `description:`, `visibility:`, and `indexingKey:`; the analyzer flags missing descriptions as SMA203). Mark VINs `visibility: .internal`, and assign `self.id` and any other plain stored property **before** `@Property`-wrapped fields in `init`.
2. **Composite Generable Inputs (`@AppEntity(.generable)`)**:
   - Use `@AppEntity(.generable)` + `TransientAppEntity` (e.g., `CarControlSettings` in `ControlCarIntent.swift`, `DriveFilterCriteria` in `FleetSiriAITypes.swift`) when Siri AI should synthesize multi-field structured arguments from natural language in a single tool call. Only a type a `@AppIntent(.tool)` takes should be generable; `CabinClimateSettings`, which only the Shortcuts action `ConfigureCabinClimateIntent` takes, is a plain `TransientAppEntity`.
   - Generable entities must have `public init() {}` and contain **only** `@Property(title:description:)` fields of primitive, `AppEnum`, or nested generable types — never put `VehicleEntity` inside a `@AppEntity(.generable)` struct.

## 5. Onscreen & Notification Grounding

- **SwiftUI Views**: Attach `.appEntityIdentifier(for: VehicleEntity.self, id: vin)` / `.appEntityIdentifier(EntityIdentifier(for: DriveEntity.self, identifier: ...))` / `.appEntityIdentifier(EntityIdentifier(for: ReleaseNoteEntity.self, identifier: ...))` to visible cards, snippets, and detail views so users can ask *"How much range does this car have?"*, *"Tell me more about this drive"*, or *"Read these release notes"*.
- **User Notifications**: Populate `UNMutableNotificationContent.appEntityIdentifiers` (as in `BatteryReminderManager.postLowBatteryNotification`) so follow-up Siri requests while viewing a notification resolve the referenced vehicle automatically.

## 6. Siri Skills Bundle (`TeslaSiri/Skills.skillsbundle/Skills/`)

- Siri-read task skills live in the **app target** at `TeslaSiri/Skills.skillsbundle/Skills/<skill-name>/SKILL.md`. Xcode compiles the bundle to `TeslaSiri.app/Metadata.appintents/Skills.skillsc`; confirm that file exists after building. SwiftPM resources and loose `.md` files are never read by Siri.
- Frontmatter: only `name` (lowercase kebab-case, equal to its folder) and `description` (≤1,024 chars, says when to use it and which sibling skill covers related requests; avoid an unquoted `: `). Any error drops every skill.
- Bodies explain the task and orchestrate tools, referring to tools by **title** ("the Get Vehicle Info tool"), never by Swift type. Don't restate tool metadata; fix the tool instead.
- `FleetSiriAIExpansionTests` validates the format and that every referenced tool title exists.

## 7. Validation Checklist

1. Run `XcodeRefreshCodeIssuesInFile` on modified Swift files.
2. Add or update Swift `Testing` coverage in `FleetKit/Tests/FleetKitTests/` (use isolated per-test `URLProtocol` sessions or `@Suite(.serialized)` if touching `MockURLProtocol`, and inject `FleetIntentService.$testingOverride` to test `@AppIntent(.tool)` `perform()` methods directly).
3. Run `BuildProject` (and check `GetBuildLog(severity: "warning")`) against an iOS 27.3 simulator destination.
4. Run `RunAllTests` / `swift test --package-path FleetKit` and confirm 100% pass rate.
5. Run `xcrun sirimetadataanalyzer <built TeslaSiri.app>` and fix new errors and warnings.
