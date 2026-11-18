# Claude Instructions

This repository is an Xcode-based SwiftUI iOS app. Claude and all other agents must use Xcode MCP tools before CLI tools for project work.

The AGENTS.md is the primary source of instructions for all AI coding agents working in this repository. While the CLAUDE.md is the primary source for Claude, the AGENTS.md may be more up to date. Make sure you check it and update the CLAUDE.md with anything it is missing, and follow that.

## Highest Priority: Use Xcode MCP First

For anything inside the Xcode project, use:

- `XcodeGlob` for project file discovery.
- `XcodeRead` for reading source and plist files.
- `XcodeGrep` for searching project content.
- `XcodeUpdate` for literal replacements in existing project files.
- `XcodeRefreshCodeIssuesInFile` for quick Swift diagnostics when available.
- `BuildProject` for builds.

Do not use shell commands as the first choice for Xcode project files. Avoid `ls`, `find`, `grep`, `sed`, `cat`, direct filesystem edits, and raw `xcodebuild` unless the Xcode MCP tools are unavailable or the task is outside the Xcode project.

Allowed CLI uses:

- Git inspection and non-destructive Git setup.
- Root-level documentation and repo metadata files.
- Files not visible through Xcode MCP (or `swift test --package-path FleetKit` per `AGENTS.md` validation checklist, or creating brand-new files inside the local `FleetKit` SwiftPM package when `XcodeWrite` rejects SwiftPM folder insertion mode).
- Explicit user requests for terminal output.

When CLI fallback is necessary for project files, explain the reason.

## Project Summary

TeslaSiri is a SwiftUI iOS 27.3+ app that connects to Tessie or Teslascope for Tesla vehicle data. It includes:

- Provider selection in Settings with separate Keychain-backed access tokens.
- Tessie and Teslascope response adapters into app-owned Fleet models.
- Observable Fleet data store.
- Local cache hydration and refresh.
- Vehicle dashboard UI.
- Drive, route, charging, software update + release notes, tire pressure, telemetry, and 21-endpoint raw export flows (see `AGENTS.md` → Tessie transport).
- Local notification payload handling and notification `appEntityIdentifiers` grounding; Tessie does not expose the old custom webhook-management API.
- FleetKit local Swift package (iOS/macOS 27.3): Siri AI `@AppIntent(.tool)` tools (vehicle telemetry, control, cabin climate, release notes readout, drive search & drive inspection, driving/charging/battery health stats), `@AppEntity(.generable)` composite inputs, `SyncableEntity` + `IndexedEntity` + `EntityStringQuery` models, bundled Siri AI workflow `SKILL.md` skills, Shortcuts, Spotlight indexing, ExtensionKit host, and shared keychain token bridge (see `AGENTS.md` → FleetKit and App Intents & `.agents/skills/siri-ai-tool-design/SKILL.md`).

## Key Files

- `TeslaSiri/ContentView.swift`: `@main` App entry point only; wires shared services into `AppRootView`.
- `TeslaSiri/UI/AppRootView.swift`: TabView shell (`AppTab` enum + `AppRootView`) and shared auth/diagnostics state.
- `TeslaSiri/UI/Dashboard/`: User-facing dashboard cards (vehicle picker, status, software, active drive, charging, cached data, sign-in banner).
- `TeslaSiri/UI/Vehicle3D/`: Live RealityKit vehicle stage (`VehicleStage`, `VehicleStageView`, `VehicleShowroomStage` Dashboard hero, `DriveReplayStage` on Drives, `VehicleRoadScene` FSD-style driving scene, `VehicleModelSpec` Tessie → build mapping). See `AGENTS.md` → Architecture Notes.
- `TeslaSiri/UI/Drives/DrivePlacesIndex.swift`, `DrivePlace.swift`, `DrivePlacesStrip.swift`: on-device index of drive destinations grouped into named places (Apple Maps POIs, Tessie saved names, detected Home), with search and place filtering on the Drives tab. See `AGENTS.md` → Architecture Notes.
- `TeslaVehicleKit/`: Vendored local package: the TeslaVehicleKit RealityKit loader plus the bundled `TeslaVehicleFleet` vehicle assets (about 225 MB).
- `TeslaSiri/UI/Dashboard/VehicleHeroArtwork.swift`: Static light/dark vehicle render (1672:941) from `VehicleAssets.xcassets`, now the 3D stage's loading placeholder and fallback.
- `TeslaSiri/UI/Drives/`: Drive demo: drive picker, route map, session summary, scrubber, metric tiles.
- `TeslaSiri/UI/Diagnostics/`: Tessie diagnostics, normalized data, Spotlight debugging, account.
- `TeslaSiri/UI/Shared/AppTheme.swift`: Shared showroom palette, `.appSurface()`, `.readableContentWidth()`, `RelativeTimeText`; see `AGENTS.md` → Design system.
- `TeslaSiri/UI/Shared/`: Reusable building blocks (`CardContainer`, `StatusBadge`, formatters, geocoder actor, `DiagnosticMonospacedValue`).
- `TeslaSiri/FleetAPI/FleetAPIClient.swift`: Tessie API client and normalized compatibility surface.
- `TeslaSiri/FleetAPI/TessieAPIModels.swift`: Tessie DTO adapters.
- `TeslaSiri/FleetAPI/FleetAPIModels.swift`: Data models.
- `TeslaSiri/FleetAPI/FleetDataStore.swift`: Observable app data state.
- `TeslaSiri/FleetAPI/FleetDataCache.swift`: Cache layer.
- `TeslaSiri/FleetAPI/FleetAccessTokenKeychain.swift`: Keychain token storage.
- `TeslaSiri/FleetAPI/FleetDeviceIdentity.swift`: Device identity.
- `TeslaSiri/FleetAPI/FleetNotifications.swift`: Local notifications and legacy webhook payload decoding.
- `TeslaSiri/FleetAPI/FleetProviderTokenStore.swift`: provider-specific token persistence and extension mirroring.
- `TeslaSiri/Info.plist`: App metadata and background task settings.
- `FleetKit/Sources/FleetKit/`: `@AppIntent(.tool)` App Intents, `SyncableEntity` + `EntityStringQuery` entities, `FleetSiriAITypes.swift` (`@AppEntity(.generable)` inputs & `VehicleCommandResultEntity`), `SiriAIWorkflowIntents.swift`, `FleetStatsAndDriveDetailIntents.swift`, `ChargeDetailsIntent.swift`, `VehicleInfoIntent.swift` (multi-topic Get Tesla Vehicle Info), `ComfortControlIntents.swift` (seat/steering wheel heat, charging amps), `CarControlStepRunner.swift` (the one sequential executor for multi-step car control; see `AGENTS.md` → Background work), `FleetStatsEntities.swift`, `FleetKitStatsModels.swift`, `FleetIntentClient`, snippet views (`FleetKitPackage`).
- `TeslaSiri/Skills.skillsbundle/Skills/`: Siri-read workflow `SKILL.md` skills (`vehicle-control`, `driving-and-energy-insights`, `overnight-security-check`, `prepare-trip`, `software-update-advisor`), compiled by Xcode into `Metadata.appintents/Skills.skillsc`. Refer to tools by title, never Swift type names. Never put skills in FleetKit resources (Siri doesn't read them) or as loose `.md` under `TeslaSiri/`.
- `.agents/skills/siri-ai-tool-design/SKILL.md`: Workspace coding-agent skill for Siri AI tool, generable entity, grounding, confirmation, and skill conventions.
- `FleetKit/Sources/FleetKit/FleetKitLog.swift`: OSLog loggers (subsystem `com.maxweinbach.TeslaSiri`) + `FleetIntentLog` perform tracker; see `AGENTS.md` → Logging (FleetKitLog) for conventions and the device-debug `ENABLE_DEBUG_DYLIB` note.
- `TeslaSiri/AppIntents/`: `FleetTokenBridge`, `TeslaSiriShortcuts` (all 10 `AppShortcut` slots used), `BatteryReminderManager`.
- `TeslaSiriAppIntents/`: thin App Intents extension re-exporting `FleetKitPackage`.

## Worktree Safety

Other agents may be editing files at the same time. Always inspect current status before making changes. Do not revert, overwrite, or clean up changes you did not make.

If source files are dirty from another task, leave them alone unless the user asked you to work on those exact files.

## Style

- Follow existing SwiftUI structure and naming.
- Prefer Swift concurrency over Combine.
- Avoid force unwraps.
- Keep UI changes scoped and consistent with the existing dashboard.
- Keep documentation precise and current with the code.
- Do not add unrelated abstractions or broad refactors.

## Validation

Use Xcode validation tools. For Swift changes, run fast diagnostics (`XcodeRefreshCodeIssuesInFile`), `swift test --package-path FleetKit` when touching `FleetKit`, and `BuildProject` when practical. For docs-only changes, verify file content and Git status.
