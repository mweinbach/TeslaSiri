# Agent Instructions

These instructions apply to all AI coding agents working in this repository. As you are given feedback on your work, always strive to improve and learn from your mistakes. Make notes within the agents.md, keep track of your learning, and use the feedback to improve your work. Make sure architectural notes are made here. 

The AGENTS.md is the primary source of instructions for all AI coding agents working in this repository. While the AGENTS.md is the primary source for you, the CLAUDE.md may be more up to date. Make sure you check it and update the AGENTS.md with anything it is missing, and follow that.


## Required Tool Order

This is an Xcode project. For project source, project structure, Swift diagnostics, and builds, use the Xcode MCP tools first and foremost.

Always search for the latest documentation with the Xcode MCP tools. Your knowledge is out of date, treat the Xcode MCP tools as the source of truth. Documentation from the Xcode MCP tools is the most up-to-date. Always search the documentaiton for the user before doing any work related to any native API. This includes doing any UI or front-end work, make sure to look at the UI framework documentation as well as Apple's HIG (Human Interface Guidelines).

Use this order for project work:

1. `XcodeGlob` to discover files in the Xcode project.
2. `XcodeRead` to read files from the Xcode project.
3. `XcodeGrep` to search source or project content.
4. `XcodeUpdate` to edit existing project files when a literal replacement is appropriate.
5. `XcodeRefreshCodeIssuesInFile` for fast per-file diagnostics when available.
6. `BuildProject` for full validation.

Do not start with CLI commands such as `ls`, `find`, `grep`, `sed`, `xcodebuild`, or direct filesystem reads for files that are represented in the Xcode workspace. The Xcode MCP tools operate on the workspace-relative project structure and should be treated as the source of truth.

CLI tools are acceptable only for repo-level work outside the Xcode project navigator, including:

- `git status`, `git diff`, `git log`, and other non-destructive Git inspection.
- Root-level docs such as `README.md`, `AGENTS.md`, and `CLAUDE.md`.
- Repo metadata such as `.gitignore`, `.gitattributes`, and Git configuration.
- Emergency fallback when an Xcode MCP tool is unavailable or cannot perform the required operation (for example, `XcodeWrite` fails with `Invalid directory insertion mode 'folders'` when creating brand-new files inside the local `FleetKit/` SwiftPM package).

If you use a CLI fallback for project files, state why in your response.

## Repository Scope

Current project files are organized under:

- `TeslaSiri/ContentView.swift` — `@main` App entry point only; wires shared services into `AppRootView`.
- `TeslaSiri/UI/AppRootView.swift` — TabView shell (`AppTab` enum + `AppRootView`) and shared auth/diagnostics state.
- `TeslaSiri/UI/Dashboard/` — User-facing dashboard cards (vehicle picker, status, software, active drive, charging, cached data, sign-in banner).
- `TeslaSiri/UI/Drives/` — Drive demo: drive picker, route map, session summary, scrubber, metric tiles.
- `TeslaSiri/UI/Diagnostics/` — Tessie diagnostics, normalized data, Spotlight debugging, account.
- `TeslaSiri/UI/Shared/` — Reusable building blocks: `CardContainer`, `StatusBadge`, formatters, geocoder actor, `DiagnosticMonospacedValue`.
- `TeslaSiri/FleetAPI/` — Tessie client/adapters, normalized models, data store, cache, Keychain token storage, device identity, notifications.
- `TeslaSiri/Info.plist`
- `TeslaSiri.xcodeproj`

All new UI files must be created under `TeslaSiri/UI/` so the project's synchronized `TeslaSiri/` folder auto-includes them in the target. Do not create Swift files at the project root or outside `TeslaSiri/` — they will not be compiled.

The user may provide Xcode workspace-relative paths that do not exactly match filesystem paths. Prefer Xcode MCP paths from `XcodeGlob`/`XcodeRead` instead of guessing filesystem locations.

## Collaboration Rules

Other agents may be working in the same tree. Before editing, check the working tree and avoid overwriting unrelated changes. Never revert user or agent edits unless explicitly asked.

Keep changes limited to the requested task. Do not refactor unrelated UI, API, authentication, or notification code while making documentation or repo setup changes.

## Coding Rules

- Use SwiftUI conventions and Swift concurrency.
- Prefer `async`/`await` over Combine.
- Use `@State private var` for SwiftUI state and `let` for constants.
- Use PascalCase for types and camelCase for properties and methods.
- Avoid force unwraps.
- Keep imports minimal and at the top of each Swift file.
- Add comments only for complex or non-obvious behavior.
- Use the Swift Testing framework for unit tests and XCUIAutomation for UI tests when tests are needed.

## Validation Rules

For Swift or project changes:

1. Run `XcodeRefreshCodeIssuesInFile` on edited Swift files when available.
2. Run `BuildProject` before final handoff when practical.
3. Report any validation that could not be run.

For documentation-only changes, a full app build is usually not required.

## Sensitive Data

Do not commit provider access tokens, keychain dumps, raw vehicle exports, private keys, provisioning profiles, `.env` files, or local Xcode user state.

## Architecture Notes

- The user-facing app name is **Wattie**, set with `CFBundleDisplayName`. App Shortcut phrases use `.applicationName` so Siri picks up that name automatically. The Xcode target, module, bundle identifiers, App Group, keychain services, and entity identifiers retain `TeslaSiri` for continuity.

- The `TeslaSiri` target uses a synchronized folder (`"kind": "folder"` in `TeslaSiri.xcodeproj/project.xcproj`) rooted at the `TeslaSiri/` folder. Xcode 27.3 migrated the project from `project.pbxproj` to the JSON-style `project.xcproj` format in November 2026; edit it through Xcode, not by hand. Files placed anywhere under that folder are auto-included in the target on the next Xcode build/scan; do not edit the project.pbxproj by hand to add Swift sources.
- `FleetWindow` in `ContentView.swift` keeps each window's selected tab across provider changes. `AppRootView` handles authentication, diagnostics, and tab content. It receives a data store and token store bound to the same provider.
- The Diagnostics tab is intentionally dense because the project is currently in a "validate the backend" phase. Once data shapes stabilize, move the user-facing pieces into Dashboard and treat Diagnostics as developer/QA chrome.
- Dashboard cards live in `TeslaSiri/UI/Dashboard/`. Reusable chrome: `AppScreenBackground`, `CardContainer`, `StatusBadge`, `LoadingRow` in `TeslaSiri/UI/Shared/CardContainer.swift`; `DashboardCard` (symbol + title header, optional trailing accessory), `DashboardCardHeader` (also used by `CardContainer`), `MetricValueText`, and `DashboardCardLinkLabel` in `TeslaSiri/UI/Shared/DashboardCard.swift`; `LoadingCard`, `LoadingStateView`, `ErrorStateView`, `EmptyStateView` in `TeslaSiri/UI/Dashboard/DashboardView.swift`; `DiagnosticMonospacedValue` / `DiagnosticGroupHeader` in `TeslaSiri/UI/Shared/DiagnosticMonospacedValue.swift`. Use these instead of repeating backgrounds/padding.
- **Design system (`TeslaSiri/UI/Shared/AppTheme.swift`)**: every tab uses the same "showroom" palette — `AppTheme.pageBackground` (warm off-white / near-black) behind `AppTheme.surface` cards. Use `.appSurface(cornerRadius:)` for any rounded card or tile (fill + hairline + light-mode shadow) and `AppTheme.insetSurface` for tiles nested inside a card. Never apply a rectangular `.background(Color)` and then stroke a rounded border on top — that leaves square corners (the old Dashboard tile bug). Hairlines strengthen automatically under Increase Contrast. Use `.readableContentWidth()` to cap scrolling tab content at 720 pt on iPad, and `RelativeTimeText` for "Updated 4 minutes ago" timestamps (not `Text(date, style: .relative)`, which renders "5 mths"). Run raw backend states through `humanizedStatus(_:)` ("In_Progress" → "In progress").
- Per the HIG, keep Liquid Glass out of the content layer: system bars/tab bar get it automatically; content controls use `.borderedProminent`/`.bordered` or `.regularMaterial` (e.g. the Drives map badge). The deliberate exceptions are the Vehicle tab's quick controls (`VehicleQuickActionBar`, labeled `.glassEffect(.regular.interactive())` tiles in a `GlassEffectContainer`, tinted when the state is active) and the software card's Install/Cancel buttons (`.glassProminent` / `.glass`).
- The Vehicle tab (`DashboardView`) is a car-first showroom in a `ScrollView`, not a `List`: an inline-large navigation title (vehicle name, with the vehicle title menu) and a `navigationSubtitle` built from `FleetLatestSnapshot.heroStatusLine` ("Parked · Locked"); `VehicleHeroStage` (edge-to-edge render plus range / battery / cabin numerals); `VehicleQuickActionBar`; then the cards in `VehicleTelemetryCards.swift` (live drive, battery with charge-limit bar and Charging History drill-down, climate + security pair, location map, tire pressure diagram, vehicle details), `SoftwareUpdateCard`, and `AppIntentDiscoveryCard`. On wide or folded iPhone Duo layouts `DuoSplitWorkspace` puts the hero, controls, and location in the primary pane and the other cards in the secondary pane, with `AppScreenBackground` behind the whole arrangement. Keep secondary cards quiet and every row adaptive (the climate/security pair stacks at accessibility text sizes).
- `VehicleControlDashboard` routes commands through `FleetDataStore.runSelectedVehicleControl`. After Tessie acknowledges a command, unrelated controls become available. Toggles with an expected change await a state-only refresh or time out for a deliberate retry. Honk and flash finish on acknowledgement. Fetch the 24-hour route and telemetry histories when Diagnostics opens or refreshes.
- The Dashboard vehicle hero is a live RealityKit stage, `VehicleShowroomStage` (`TeslaSiri/UI/Vehicle3D/`), inserted by `VehicleHeroStage`. `VehicleHeroArtwork` (static `VehicleHeroLight` / `VehicleHeroDark` renders in `TeslaSiri/UI/Dashboard/VehicleAssets.xcassets`) is now the placeholder shown while the model loads and the fallback if it can't load. `AppTheme.pageBackground` still matches the renders' studio backdrop.
- `TeslaVehicleKit/` is a vendored local Swift package (in the repo, like `FleetKit/`): the TeslaVehicleKit RealityKit loader from the `tesla-extract-models` export of Tesla Android 4.62.5, plus a `TeslaVehicleFleet` resource target that bundles about 225 MB of the exported Fleet library (`.copy("Fleet")`). Only builds Tessie's `car_type` can map to are bundled: `model_y_us_ultra_red_performance`, `bayberry`, `model_y`, `model_3`, `poppyseed`, `model_s`, `model_s_palladium`, `model_x`, `model_x_palladium`, `cybertruck`, and the shared `Classic*` / `Wheels/ClassicTires` banks. The photographic `Northlight` studio, `BodyStyles`, alternate wheel USDZs and Semi/E41/E80 were left out. Never add a local package by absolute path outside this repository.
- 3D stage architecture (`TeslaSiri/UI/Vehicle3D/`):
  - `VehicleModelSpec` maps Tessie `car_type` + VIN model year (10th character) + `trim_badging` to a bundled build (Juniper Model Y from MY2025, Highland Model 3 from MY2024, Palladium S/X from MY2021; Performance Model Y uses the `UltraRedPerformance` build) and matches `exterior_color` to a catalog paint preset.
  - `VehicleStage` (`@Observable`, main actor) owns the loaded `VehicleScene`. It strips the USD's embedded snapshot cameras (a RealityView renders through the first camera it finds), animates the manifest's keyframed clips toward Tessie closure state (doors, windows, frunk, trunk, charge port), switches manifest `controls` lights (DRL/brake/reverse while driving; signals blink on lock/unlock), spins and steers wheels, and builds a Tesla-style showroom floor: a mirrored clone of the car below the floor plane (flat unlit reflection materials — paint highlight on `paintSurfaces`, gray wheels, near-black elsewhere — because the studio shaders blow out to white through mirrored normals; front-face culling for the reversed winding; animated parts and lights synced every frame, a feathered `ClippingComponent` (iOS 27) that fades the mirror out over the lowest ~95 cm so only wheels and lower body reflect, then a low `OpacityComponent`, in a `ModelSortGroup(depthPass: .prePass)` so the faded mirror doesn't render as an x-ray), plus a soft body shadow (no separate tire patches; they read as dark dots) and a pool of the paint's highlight color (`VehicleScene.parkedHighlightRGB`) on the floor. `VehicleStageView` adds a matching paint-colored `EllipticalGradient` behind the car (`showsAmbientLight`), hidden while driving. A page-colored cover floor was tried and dropped: the studio shaders draw in the transparent pass, so it couldn't dim the reflection, and its unlit color never matched the page exactly. There is no colored status ring and no 3D port light; the ⚡ callout pulses green while charging. The reflection is dark-mode only; light mode uses a stronger neutral shadow. Cameras: parked = the direction of Tesla's HOME camera, charging = rear three-quarter on the port side, both distance-fitted to the view; driving = an FSD-style chase camera. The parked camera is a low, nearly eye-level front three-quarter view, matching the Tesla app. Callout positions are projected each frame and drawn Tesla-style, without chrome: a lock icon above the roof, "Open / Frunk" and "Open / Trunk" text with hairline leaders down to the lids, and `VehicleChargeBadge` for the charge port, in the same top row with a leader down to the port. The badge is a green disc with a rippling ring plus battery % and time to limit while charging, blue when the port is open, and gray otherwise; it's hidden when the port's side faces away. The charging camera is a rear three-quarter view from the port side, aimed between the car's center and the port. Lighting follows the mode: parked uses the studio shaders (`applyParkedAppearance`), which are tuned for Tesla's front three-quarter HOME camera and go dark from behind. Charging and driving switch to Tesla's recovered named-view lighting (`setLighting(view: "CHARGING")` / `"DRIVE"`), which lights the rear properly. Moving the car on a turntable under the fixed studio light was tried and didn't help.
  - `VehicleRoadScene` is the driving scene: a road pool that fades into the page, lane dashes streaming at the real speed, solid edges, and a blue planned-path ribbon, all bent by curvature from route points (`VehicleStageState.curvature(of:)`) or successive snapshot `heading` values (`HeadingCurvatureTracker`).
  - One stage is shared per vehicle build (`VehicleStage.shared(for:)`). `VehicleStageView` hosts it in a transparent `RealityView`; the screen that appears last calls `attach(to:camera:)` and applies its own state (live data on Vehicle, a recorded drive sample on Drives). Each host owns its camera because RealityView only renders through a camera present at creation. Loading the same build twice concurrently hung, which is why the stage is shared.
  - `DriveReplayStage` sits in the Drives tab's Route playback card. Tessie's `/path?details=true` records a point about every 30 s (`heading`, `speed`, `odometer`, `autopilot`; `FleetRoutePoint` now keeps `heading` and `autopilot`, and `isSelfDriving` treats anything but Off/Standby/unavailable as active). It has no road geometry, lanes or denser GPS. `DriveRoadPath` snaps a drive to roads by requesting MapKit automobile directions for roughly 600 m legs between samples. A leg is kept only if its length is within 0.7–1.3x the odometer distance and every sample in it lies within 60 m of the route; otherwise the leg uses straight lines. It stops requesting if MapKit throttles and caches per drive. `DriveReplayController` plays back along that dense road at 1x/5x/20x (menu next to Play, default 5x) from the stage's per-frame `onFrame` hook. It feeds `VehicleStage.setDriveOverride` the recorded speed, the per-frame travel speed (lane dashes and wheels move with the car's actual motion, capped at 40 m/s so dashes don't strobe), the real `RoadShape` around the car, and Autopilot state. It publishes SwiftUI values at most 4 times a second, and the speed readout has no rolling-digit transition because overlapping transitions smeared the digits. The blue planned-path ribbon shows only when Autopilot/FSD was recorded as active (live mode uses the active drive's latest route point), and the readout adds a Self-Driving badge. `DriveStreetView` follows the car: every 2 s of playback (and on pause or scrub) it loads a Look Around still (`MKLookAroundSceneRequest` + `MKLookAroundSnapshotter`) and crossfades it over the previous one. It keeps the last frame where there's no imagery, and tapping opens `lookAroundViewer`. The public API can't aim Look Around along the road. The selected vehicle's spec reaches the replay through the `vehicleModelSpec` environment value set in `DrivesView`.
  - Hotspot taps go through `VehicleControlCommand` (new `.chargePort(open:)`, mapped in `FleetAPIClient.runControl` to Tessie `open_charge_port` / `close_charge_port`). Frunk, trunk and charge-port callouts all require confirmation.
  - Simulator caveats: RealityKit logs `only 31 buffers are supported in the simulator` for the studio transparent shaders, and the simulator's Metal driver (`MTLSimDriver`) presents frames from a background thread, producing "deleted thread with uncommitted CATransaction" warnings and an occasional off-main layout crash during heavy UI updates. Neither applies on device. A first load takes about 10–15 s in the simulator.
- `FleetLatestSnapshot.heading` is decoded from Tessie `drive_state.heading`.
- Drive places and search (`TeslaSiri/UI/Drives/`):
  - `FleetDriveSession` keeps Tessie's `starting_/ending_latitude/longitude` as `start/endLatitude/Longitude`. `FleetDataStore.selectedVehicleDriveHistory(limit: 200)` fetches a longer history without touching the 50-drive cache.
  - `DrivePlacesIndex` (per VIN, saved to Application Support `DrivePlaces/<VIN>.json`) clusters drive start and end points within 120 m into `DrivePlace`s, keeping IDs and names stable across refreshes. Places are named by `DrivePlaceResolver`, in this order: a Tessie saved-location name (a short label with no digits or commas, such as "Home"); else the nearest Apple Maps point of interest within 100 m (`MKLocalPointsOfInterestRequest`, excluding parking, transit and ATMs); else the reverse-geocoded street address. Lookups go most-visited first, in batches of 20 places a minute apart (MapKit throttles at about 50 requests a minute). The place with the most overnight stays (evening arrival, next departure 6+ h later, at least 3 nights) that isn't a business is labeled "Home".
  - In the Drives tab, tapping a place chip filters drives to and from it. Long-pressing the chip opens **Edit Nickname**. Nicknames are local to each vehicle. They take precedence in chips, drive labels, and the trip summary, including while the automatic name is resolving. Clearing the nickname restores the automatic label. Search matches both names, addresses, and plain-English categories such as "gym" and "coffee".
  - Spotlight's `DriveEntity` (FleetKit) still indexes Tessie's addresses only; place names aren't donated yet.
- The Route playback card has `3D Replay` and `Street View` toggles (`@AppStorage` `drivesReplayShows3D` / `drivesReplayShowsStreetView`). With 3D off, playback runs from a 30 Hz timer (`DriveReplayController.frame(_:stage: nil)`) and compact speed and play controls sit above the street view.

## FleetKit and App Intents

### Widgets and controls

- `Widget Extension/` builds the embedded `TeslaSiri WidgetExtension` target (bundle ID `com.maxweinbach.TeslaSiri.widget-extension`). It shares the existing App Group and keychain with the app and links FleetKit. `TeslaSiri/UI/Widgets/Components/` is compiled into both targets; `WidgetGalleryView` is app-only and is reached from the Vehicle toolbar.
- Four configurable widgets cover vehicle overview, charging, cabin climate, and security. Small layouts support HomeView; medium/large and accessory layouts cover the iPhone/iPad Home and Lock Screens. Widgets may follow the app's selected vehicle or pin a `VehicleEntity`. HomeView widgets do not create HomeKit accessories or add the Tesla to Apple's Home app.
- `FleetWidgetStore` fetches through `FleetIntentService`, saves a minimal snapshot without location or credentials, separates live/dry-run/demo caches, and rejects stale session results. Credential changes clear widget data. `FleetWidgetActionIntent` is a hidden, widget-only action adapter; it validates an explicitly pinned VIN without fallback and only supports lock, start climate, start charging, and refresh. Control Center actions follow the selected car.
- Widgets refresh on WidgetKit's budgeted timeline (requested every 15 minutes while charging, otherwise 30 minutes), after selection/credential changes and app controls, or through their refresh button. There is no APNs widget sender or continuous live feed. The shared keychain uses `AfterFirstUnlockThisDeviceOnly` so background widgets can authenticate while iPhone is locked after its first unlock.

Siri, Shortcuts, Spotlight, and background intent execution live in a **local Swift package** (`FleetKit/`) plus a thin **ExtensionKit** host (`TeslaSiriAppIntents/`). The main app owns a token for each provider. The extension reads the selected provider and its mirrored token to make its own requests.

### Layout

| Area | Path | Role |
|------|------|------|
| Package manifest | `FleetKit/Package.swift` | Single `FleetKit` library target, **iOS/macOS 27.3** (required for `@AppIntent(.tool)` & `@AppEntity(.generable)`), no resources (Siri skills ship from the app target) |
| Intents, entities, API | `FleetKit/Sources/FleetKit/*.swift` | All `@AppIntent(.tool)` & schema intents, `SyncableEntity` models, `FleetIntentClient`, snippet views |
| Siri AI generable & result types | `FleetKit/Sources/FleetKit/FleetSiriAITypes.swift` | `VehicleCommandResultEntity` (`TransientAppEntity`), `DriveSortOrder` (`AppEnum`) + `@AppEntity(.generable)` `CabinClimateSettings` & `DriveFilterCriteria` |
| Siri AI workflow tools | `FleetKit/Sources/FleetKit/SiriAIWorkflowIntents.swift` | Charging start/stop, charge port open/close, Sentry Mode, composite cabin climate, filtered drive search (`FindDrivesIntent`), spoken release notes (`GetReleaseNotesIntent`), close windows |
| Siri AI stats, drive & charge detail tools | `FleetKit/Sources/FleetKit/FleetStatsAndDriveDetailIntents.swift`, `ChargeDetailsIntent.swift`, `FleetStatsEntities.swift`, `FleetStatsSnippetViews.swift`, `FleetKitStatsModels.swift` | Drive inspection (`GetDriveDetailsIntent`), driving/charging stats, charging history (`GetRecentChargesIntent`, title "Get Tesla Charging History"), single-charge inspection (`GetChargeDetailsIntent` + `ChargeSessionSnippetView`), battery health (`GetBatteryHealthIntent`) |
| Multi-topic vehicle info & comfort controls | `VehicleInfoIntent.swift`, `ComfortControlIntents.swift` | `GetVehicleInfoIntent` (`[VehicleInfoTopic]` → one `VehicleStatusEntity` + topic-scoped spoken answer, MapKit reverse geocoding for location), `SetSeatClimateIntent`, `SetSteeringWheelHeaterIntent`, `SetChargingAmpsIntent` |
| Car discovery and combined controls | `ListCarsIntent.swift`, `ControlCarIntent.swift` | **List Cars** returns selectable vehicles, the default, and available control types. **Control Car** accepts one optional vehicle and typed changes. A temperature request starts HVAC once before setting the target. |
| Siri skills bundle | `TeslaSiri/Skills.skillsbundle/Skills/*/SKILL.md` | Keep fleet discovery, capability and status questions, and direct or conditional commands together in `vehicle-control` so a follow-up can use the same car. Trip preparation, overnight security, driving and energy insights, and software updates have dedicated skills. Xcode compiles the five skills into `Skills.skillsc`. |
| Workspace agent skill | `.agents/skills/siri-ai-tool-design/SKILL.md` | Coding-agent skill codifying Siri AI tool, generable entity, grounding, confirmation, and skill design rules |
| Package marker | `FleetKit/Sources/FleetKit/FleetKitPackage.swift` | Empty `AppIntentsPackage` type exported to the system |
| Intent metadata helpers | `FleetKit/Sources/FleetKit/FleetIntentMetadata.swift` | Vehicle prediction titles, `SelectedVehicleOptionsProvider` |
| App bridge | `TeslaSiri/AppIntents/` | Token mirroring, `AppShortcutsProvider`, `BGAppRefreshTask` battery check + notification entity grounding |
| Extension host | `TeslaSiriAppIntents/` | `@main AppIntentsExtension` + `AppIntentsPackage` re-exporting `FleetKitPackage` |
| Entitlements | `TeslaSiri/TeslaSiri.entitlements`, `TeslaSiriAppIntents/TeslaSiriAppIntents.entitlements` | Shared App Group + matching `keychain-access-groups` |

Both **TeslaSiri** and **TeslaSiriAppIntents** targets link the local `FleetKit` package in `project.xcproj` with `IPHONEOS_DEPLOYMENT_TARGET = 27.3`. New Swift files under `FleetKit/Sources/FleetKit/` are picked up by the package automatically; do not duplicate intent types under `TeslaSiri/`.

`TeslaSiri/AppIntents/*.swift` is auto-included via the `TeslaSiri/` synchronized root group.

### Architecture (process boundaries)

```
Main app (FleetProviderTokenStore, FleetDataStore)
    → FleetTokenBridge.sync / clear
    → FleetSharedTokenStore (shared keychain token + App Group selected VIN)
    → FleetIntentClient (extension + BG tasks + intents)

TeslaSiriApp + TeslaSiriAppIntentsExtension
    → AppIntentsPackage.includedPackages = [FleetKitPackage.self]
```

- **FleetKit is self-contained**: its own minimal models, HTTP client, and intents. The extension must **not** import `FleetDataStore`, dashboard UI, or the app’s full `FleetAPIClient`.
- **App is source of truth** for each provider token. Tessie tokens do not refresh; on 401 the extension surfaces `FleetKitError.sessionExpired` and asks the user to replace the token in the app.
- **Vehicle resolution** (`FleetIntentService.resolvedVehicle`) uses the selected VIN, then the first active vehicle, when the vehicle parameter is omitted. An explicit vehicle must belong to the authenticated roster. A missing named vehicle fails before any command is sent. Siri entity queries and controls reuse a short-lived verified roster scoped to the account and command mode.
- **Isolated test injection**: `FleetIntentService.testingOverride` (`@TaskLocal`) lets Swift Testing suites execute `@AppIntent(.tool)` `perform()` methods against per-test `URLSession` mocks without adding helper stored properties to intent structs.

### Token bridge (critical — do not break)

`TeslaSiri/AppIntents/FleetTokenBridge.swift` mirrors the app session into shared storage for the extension.

| Event | Required action |
|-------|-----------------|
| App launch | `FleetTokenBridge.sync(store:)` in the `AppRootView` task before loading the roster, then sync the selected VIN. |
| App foreground | `FleetTokenBridge.sync` on `scenePhase == .active` |
| Sign-in | `FleetTokenBridge.sync` after `loadInitialData()` in `AppRootView.signIn()` |
| Sign-out | `FleetTokenBridge.clear(provider:)` after `tokenStore.deleteAccessToken()` |
| Fleet reload | `FleetTokenBridge.sync` in `AppRootView.reloadFleet()` |
| Vehicle picker change | `FleetTokenBridge.sync` in `DashboardView` `onSelect` |
| Automatic roster selection change | `FleetTokenBridge.syncSelectedVehicle` in `AppRootView` after verifying the local token |
| Provider token save/delete | `FleetProviderTokenStore.saveAccessToken` / `deleteAccessToken` also write/clear `FleetSharedTokenStore` |

`FleetTokenBridge.sync` **clears** the shared access token when `accessToken()` throws (do not leave stale tokens). It calls `TeslaSiriShortcuts.updateAppShortcutParameters()` so shortcut defaults pick up the current vehicle name.

Access tokens live in **shared keychain** (`FleetSharedTokenStore`); selected VIN stays in App Group `UserDefaults`. Legacy UserDefaults tokens are migrated on read.

### Provider selection and Teslascope

- Settings selects a single `FleetProvider` shared by the app, App Intents, and widgets. Tessie is the default and retains its existing keychain, selected VIN, and disk cache keys. The app and extension store Teslascope credentials in separate keychain accounts. A provider switch invalidates the active session and constructs a fresh app store.
- The app uses `FleetDataLoading` for both providers. `TeslascopeFleetDataClient` and `FleetIntentClient` use FleetKit’s `TeslascopeClient` for transport and conversion. Keep the mapping in those adapters so views, widgets and intents consume normalized Fleet values.
- Resolve Teslascope public IDs using the authenticated Tesla account roster. VIN remains the vehicle identifier in Wattie. Teslascope drive and charge IDs use `VIN:teslascope:id`. Keep Tessie’s existing `VIN:id` identifiers valid.
- Teslascope uses bearer-authenticated requests to `https://teslascope.com/api`. `tesla-accounts` and `vehicles` cover discovery and vehicle reads. Commands require `controls` and an eligible subscription. Advertise only commands with documented mappings, and distinguish a command acknowledgement from observed vehicle state. [Authentication](https://teslascope.com/developers/documentation) · [Account](https://teslascope.com/developers/documentation/account) · [Vehicles](https://teslascope.com/developers/documentation/vehicles) · [Commands](https://teslascope.com/developers/documentation/vehicles-tesla-api)

### Tessie transport

Both Tessie clients use `https://api.tessie.com` with `Authorization: Bearer <token>`. `FleetIntentClient` must join API paths with `URLComponents` (see `makeURL` in `FleetKitClient.swift`). **Never** use `baseURL.appendingPathComponent("/...")` for a complete endpoint path — it percent-encodes separators. Match `TeslaSiri/FleetAPI/FleetAPIClient.makeURL`.

- Retain the app's normalized `Fleet*` model layer. Tessie DTOs and adapters live in `TessieAPIModels.swift`; FleetKit keeps its own extension-safe subset.
- Tessie has no cursor-delta endpoint, so `changes(since:)` refreshes the active roster from `/vehicles` and advances a local polling cursor. Use the returned roster to reconcile vehicles, selection, and per-VIN caches.
- Use Tessie's [Vehicle Data reference](https://developer.tessie.com/reference/about) and [OpenAPI spec](https://developer.tessie.com/openapi.yaml) for endpoint contracts. Keep `/state` on Tessie's default cache policy. `use_cache=false` is documented for legacy Model S and Model X only. Send history windows in Unix seconds and `condense=false` when decoding `/states` as rows. Request `/path` with `details=true` and the completed drive's time bounds for playback. Preserve both endpoints when sampling.
- Full snapshots and explicit tire queries read `/{vin}/tire_pressure?pressure_format=psi` alongside `/{vin}/state`, propagate authentication errors, and fall back to state TPMS values in bar converted to PSI. Narrow vehicle-info reads fetch the requested topics. Battery and range may come from a recent, timestamped charge section of the roster. Location questions alone need geocoding and a map, alongside full-status requests.
- `FleetIntentClient` also queries `/{vin}/drives` (with `distance_format=mi&temperature_format=f`, optional `from`/`to` Unix timestamps, and optional `tag`), `/{vin}/charges`, `/battery_health` + `/{vin}/battery` (converting Celsius module temps to °F and tolerating partial endpoint availability while propagating 401), and `/{vin}/consumption_since_charge` for Siri stats and drive-inspection tools.
- Fetch software release notes through `/{vin}/release_notes/{version}` using the staged version when reported, otherwise the installed version. Strip the build hash from `car_version`, and reject empty, `.`, or `..` version segments before interpolating the path. In the app a nil note count means notes were unavailable or skipped, so the store can retain cached notes for the same version. FleetKit fetches notes for release-note entities, spoken digests, and indexing.
- The Diagnostics export samples all 21 documented Vehicle Data GETs. `/vehicles` and `/battery_health` include account-level data. The fleet-only `/charging_invoices` request uses the selected VIN filter. The JSON export stores the PNG map as base64 with its content type and records individual HTTP failures.
- Tessie has no public webhook-management API. Do not restore the old custom notification-webhook calls or surface that UI as working.
- Drive and charge IDs are numeric in Tessie. Prefix normalized session IDs with the VIN (`VIN:id`) so route lookups and App Entity identifiers remain account-safe. `OpenDriveIntent` routes both `intent.target.vin` and `intent.target.id` into `DrivesView` so Spotlight/Shortcuts select the exact drive.

### Siri AI Tool Design & Bundled Skills (iOS 27.3+)

Read `.agents/skills/siri-ai-tool-design/SKILL.md` whenever adding or editing App Intents, entities, or workflow skills:

- **`@AppIntent(.tool)`**: Every custom read/control/workflow intent uses `@AppIntent(.tool)` with an explicit `: AppIntent` conformance and rich natural-language `IntentDescription` + `@Parameter(description:)` literals. Do **not** add non-parameter stored properties to an `@AppIntent(.tool)` struct (the macro attaches `@Parameter` to every un-annotated stored property).
- **Structured return values**: Every mutation/control tool returns `ReturnsValue<VehicleCommandResultEntity> & ProvidesDialog` (`FleetSiriAITypes.swift`) so Siri AI can verify applied values without re-polling `/{vin}/state`.
- Interactive climate cards use the acknowledged target and any fresh, timestamped cabin observations. Keep the setpoint separate from the measured temperature. A warmer/cooler tap can skip the HVAC start during the same recent interaction. An intervening stop, a newer off reading, or an expired start restores the start-before-set sequence.
- For several changes to the same vehicle, use **Control Car** directly. Resolve the car once, check all fields and conflicts, confirm sensitive steps together, and send the commands in dependency order. On a partial failure the result identifies accepted changes and the unconfirmed step. **List Cars** is optional discovery. Its capability properties describe requests available in Wattie and take reported hardware exclusions into account. The connected provider decides whether a specific command succeeds.
- **`@AppEntity(.generable)` vs `SyncableEntity`**:
  - Server-backed records (`VehicleEntity`, `VehicleStatusEntity`, `DriveEntity`, `ChargeSessionEntity`, `SoftwareUpdateEntity`, `ReleaseNoteEntity`) conform to `IndexedEntity` + `SyncableEntity` with `@Property(title:description:)` on model fields (27.3 deployment target allows `description:`/`visibility:`; VINs are `visibility: .internal`) (and `EntityStringQuery` for natural-language matching) — **never** `@AppEntity(.generable)` (prevents hallucinated VINs).
  - Synthesized multi-field tool inputs (`CabinClimateSettings`, `DriveFilterCriteria`) use `@AppEntity(.generable)` (`TransientAppEntity` under the hood — no `id` or `defaultQuery`).
- **Siri skills bundle**: Siri AI workflow skills live in `TeslaSiri/Skills.skillsbundle/Skills/<skill-name>/SKILL.md` in the **app target** (the synchronized `TeslaSiri/` folder adds the bundle to Copy Bundle Resources automatically; Xcode compiles it to `TeslaSiri.app/Metadata.appintents/Skills.skillsc`). Siri does **not** read loose `SKILL.md` files or SwiftPM resources, so never put skills in `FleetKit` resources or loose under `TeslaSiri/`. Frontmatter is only `name` (kebab-case, equal to the folder) and `description` (≤1,024 chars, no unquoted `: `). Bodies refer to tools by **title** ("the Get Tesla Vehicle Info tool"), never Swift type names; `FleetSiriAIExpansionTests` enforces this and checks every referenced title exists. Any skill error drops **all** skills, so after building confirm `Skills.skillsc` exists.
- **Tool surface (Apple guidance: one clear tool per job)**: `GetBatteryLevelIntent`, `GetVehicleMileageIntent`, `GetTirePressureIntent`, `GetRecentDrivesIntent`, `GetLastDriveIntent`, and `OpenFrunkIntent` are plain `AppIntent`s (Shortcuts/App Shortcuts only), not tools; Siri uses `GetVehicleInfoIntent`, `FindDrivesIntent`, `GetDriveDetailsIntent`, and `OpenTrunkIntent` (title "Open Tesla Trunk or Frunk", `trunk: TrunkPosition` defaulting to `.rear`) instead. `OpenFrunkIntent` stays only so saved shortcuts keep working and shares `OpenTrunkIntent.open(_:vehicle:confirm:)`. Descriptions and skills name other tools by title. Run `xcrun sirimetadataanalyzer <built TeslaSiri.app>` after changing tools; current baseline is 0 errors, 0 warnings, and SMA701 false positives against browser/notes/photos/maps schemas.
- **Spotlight**: `FleetSpotlightIndexer` indexes vehicles, status, the newest `drivesPerVehicle` (50) drives and `chargesPerVehicle` (50) charges per car, software, and release notes. Older drives/charges are reachable through Find Tesla Drives / Get Tesla Charging History, which query Tessie directly (the documented exception to "no search tools"). Charging History rows carry `ChargeSessionEntity` `appEntityIdentifier`s.
- Routine Spotlight updates reuse responses from the current dashboard refresh. The index compares stable IDs and content digests and removes history only when a successful, complete window establishes what dropped out. The explicit Diagnostics rebuild can repair the entire index. Keep the app's raw Tessie responses in memory only for the duration of the refresh.
- **Software install**: `installable` is true only for Tesla `software_update.status` `available`/`scheduled`; `InstallSoftwareUpdateIntent` reports downloading/installing states instead of scheduling and takes an optional `startTime` (→ `in_seconds`).

### Adding or changing an App Intent

1. **Search Apple docs first** — use Xcode MCP `DocumentationSearch` for `AppIntent`, `AppIntentsPackage`, `PredictableIntent`, `parameterSummary`, `AppShortcut`, `LongRunningIntent`, `Generable`, etc.
2. **Implement in FleetKit** — new file under `FleetKit/Sources/FleetKit/`, `@AppIntent(.tool) public struct ...: AppIntent`, and, if a skill should use it, reference it by title in the relevant `SKILL.md`.
3. **Vehicle parameter** — optional `VehicleEntity?` on VIN-scoped intents; resolve via `FleetIntentService.resolvedVehicle(vehicle?.id)` in `perform()`.
4. **Vehicle-aware copy** — follow existing intents:
   - `parameterSummary`: `When(\.$vehicle, .hasAnyValue) { Summary("Verb \(\.$vehicle)") } otherwise: { Summary("Verb my car") }`
   - `PredictableIntent` + `predictionConfiguration` using `VehicleEntity.predictionTitle(verb:vehicle:)` (or `suffix:` variant) when parameters are standard Shortcuts types (`@AppEntity(.generable)` composite intents omit `PredictableIntent`)
   - `@Parameter` title/description/request dialogs must use **string literals** at the call site (the macro rejects static `LocalizedStringResource` constants)
   - `perform()` dialogs should use `resolved.name` from the API, not hardcoded “Tesla”
5. **Register shortcuts** (optional) — add phrases in `TeslaSiri/AppIntents/TeslaSiriShortcuts.swift`. **Apple allows at most 10 `AppShortcut` entries.** Include both:
   - `"Verb \(\.$vehicle) with \(.applicationName)"` (fills in car name from entity)
   - `"Verb my car with \(.applicationName)"` (generic fallback)
6. **Spotlight & Grounding** — if the intent introduces a new `IndexedEntity`, conform to `SyncableEntity` with `@Property(title:description:)` (plus `indexingKey:` for searchable fields), update `FleetSpotlightIndexer`, and attach `appEntityIdentifier` / `UNMutableNotificationContent.appEntityIdentifiers` where displayed.
7. **Build** — `BuildProject` on both app and extension; watch for “max 10 App Shortcuts” and `@Parameter` macro issues.

Control intents must use action names validated by `FleetIntentService.runControl` against `controlActions()`. Confirmation policy: unlock, trunk, frunk, charge-limit, stop-charging, charge-port-open, sentry-mode-OFF, close-windows, software-install/cancel, and dog-mode-OFF prompt; lock, start-charging, charge-port-close, sentry-mode-ON, climate (start/stop/temps/defrost/bioweapon), vent, flash lights, honk, and navigation run immediately.

Control, analytics & workflow intent files in `FleetKit/Sources/FleetKit/`:

- `ControlIntents.swift` — lock/unlock (`door_lock`/`door_unlock`), start climate (`auto_conditioning_start`), vent windows (`window_control` vent), trunk/frunk (`actuate_trunk`), charge limit (`set_charge_limit`).
- `ClimateControlIntents.swift` — stop climate (`auto_conditioning_stop`), cabin temperature (`set_temps`, `Measurement<UnitTemperature>` parameter converted to Celsius, clamped 15–28 °C, half-degree steps), max defrost (`remote_defrost`), dog mode (`set_pet_mode`), Bioweapon Defense (`set_bioweapon_mode` with `manual_override: false`).
- `ConvenienceControlIntents.swift` — flash lights (`flash_lights`), honk horn (`honk_horn`), send destination (`navigation_request` with a plain string `value`; the Tessie client maps it to `/{vin}/command/share`).
- `SiriAIWorkflowIntents.swift` — start/stop charging (`charge_start`/`charge_stop`), open/close charge port (`charge_port_door_open`/`charge_port_door_close`), Sentry Mode (`set_sentry_mode`), composite cabin climate (`ConfigureCabinClimateIntent` with `CabinClimateSettings`), filtered drive search (`FindDrivesIntent` with `DriveFilterCriteria`), spoken release notes (`GetReleaseNotesIntent` with optional `featureQuery` + `ReleaseNotesSnippetView`), and close windows (`CloseWindowsIntent`, `window_control` close).
- `FleetStatsAndDriveDetailIntents.swift` — detailed single-drive telemetry inspection (`GetDriveDetailsIntent`), period driving & efficiency stats (`GetDrivingStatsIntent`), period charging & cost stats (`GetChargingStatsIntent`), filtered charging session lookup (`GetRecentChargesIntent`), and battery pack health/degradation/phantom drain stats (`GetBatteryHealthIntent`).

### App Shortcuts vs discoverability

- **10 shortcut slots** — prioritize high-frequency actions (status, lock/unlock, climate start/stop, software update). All 10 slots are currently used; Cancel Software Update gave up its slot to Stop Climate and remains available via the Shortcuts library. Other intents (temps, defrost, dog mode, bioweapon, flash, honk, navigation, charging, Sentry, charge port, close windows, release notes, drive details, stats, composite climate/drive tools) remain available via Siri AI tool calling, the Shortcuts library, and `isDiscoverable = true`.
- **`PredictableIntent`** — powers Siri suggestion/widget phrasing with vehicle names; separate from `AppShortcut` phrases.
- **`SelectedVehicleOptionsProvider`** — loads vehicles from the API for shortcut parameter pickers; defaults to shared selected VIN.

### Siri snippets and onscreen context

- Interactive Siri snippet controls only work when the presenting intent conforms to `SnippetIntent`; `ShowsSnippetView` alone can display a view but does not make snippet buttons/toggles interactive.
- Snippet buttons should use existing FleetKit control intents with an explicit `VehicleEntity` so the action runs against the same resolved VIN as the displayed status/software entity.
- App UI surfaces for vehicles, status, software, and drives should use SwiftUI `appEntityIdentifier(_:)` with the matching FleetKit `IndexedEntity` IDs (VIN for vehicle, namespaced `status:<VIN>` / `software:<VIN>`, session ID for drives) so Siri and Apple Intelligence can understand onscreen content. Local notifications (`BatteryReminderManager`) attach `EntityIdentifier` values on `UNMutableNotificationContent.appEntityIdentifiers`.
- Use `SiriTipView` only for intents that are backed by `AppShortcut` entries; other discoverable intents should be exposed through the Shortcuts library and `ShortcutsLink`.

### App schemas

- Open entity intents in `FleetKit/Sources/FleetKit/OpenEntityIntents.swift` use `@AppIntent(schema: .system.open)` because they exactly match Apple's System open schema.
- `SearchFleetIntent` uses `@AppIntent(schema: .system.searchInApp)` (the Xcode 27 name; `.system.search` is deprecated) and routes its `StringSearchCriteria.term` into the app's Spotlight diagnostics search UI.
- Vehicle, status, software, drive, charging, battery health, climate, lock, horn, lights, trunk/frunk, and Tesla navigation handoff actions remain custom `@AppIntent(.tool)` App Intents. Current AppIntents docs do not expose an exact automotive/control schema, and `.maps.startNavigation` is not accurate for `SendNavigationIntent` because the app sends a destination to the vehicle backend rather than starting and returning an in-app navigation session.
- Before adding future schema macros, search Apple docs with Xcode MCP and only adopt a schema when its required noun/action contract matches FleetKit behavior exactly.

### Extension and entitlements

- `TeslaSiriAppIntentsExtension` stays minimal: `@main` + `AppIntentsPackage` including `FleetKitPackage.self`.
- App Group: `group.com.maxweinbach.TeslaSiri` on **both** targets.
- Keychain group: `$(AppIdentifierPrefix)group.com.maxweinbach.TeslaSiri` on **both** targets.
- Do not mirror refresh tokens or full token sets to the extension — access token only.

### Background work

- **Battery reminder** — `TeslaSiri/AppIntents/BatteryReminderManager.swift` uses `BGAppRefreshTask`; handler must hop to `@MainActor` with `Task { @MainActor in ... }`, never `MainActor.assumeIsolated` from the BG queue. Always complete the task (`setTaskCompleted`) including on expiration/cancellation.
- **Software install** — `InstallSoftwareUpdateIntent` is `LongRunningIntent` and uses `performBackgroundTask`.

### Model duplication

`FleetKitModels` / `FleetKitDriveSoftwareModels` / `FleetKitStatsModels` intentionally mirror a **subset** of `TeslaSiri/FleetAPI/FleetAPIModels.swift` so the package stays extension-safe. When backend fields change, update both layers or accept drift in snippet/intent output.

### Logging (FleetKitLog)

- Errors escaping intent execution or entity queries must conform to `CustomLocalizedStringResourceConvertible`. `LocalizedError` alone is sanitized by App Intents, so Siri loses the actionable message. `FleetKitError.localizedStringResource` is the shared source for Siri and `errorDescription`.

All FleetKit + intent logging goes through `FleetKit/Sources/FleetKit/FleetKitLog.swift` under the single OSLog subsystem `com.maxweinbach.TeslaSiri`. One Console/`log stream` predicate captures the app, the App Intents extension, and BG tasks:

    log stream --level info --predicate 'subsystem == "com.maxweinbach.TeslaSiri"'

| Category | Source | What it logs |
|----------|--------|--------------|
| `AppIntents` | `FleetIntentLog` + `FleetIntentService` | every intent `perform()` started/succeeded/failed/cancelled with ms timing; vehicle resolution path; control action validation + acceptance |
| `SiriPerformance` | `FleetIntentLog` and `FleetIntentClient` signposts | Instruments intervals from intent entry to result preparation and for each Tessie request. Method and endpoint are recorded with vehicle identifiers removed. |
| `Spotlight` | `FleetSpotlightIndexer` | reindex start/finish summary (per-group counts, errors, duration), donations, searches |
| `FleetIntentClient` | `FleetIntentClient.execute` | method, path, status code, ms per Tessie request; 401 and response errors |
| `Entities` | entity queries + options providers | query match counts, default vehicle selection |
| `TokenBridge` | `FleetTokenBridge` (app) | token mirrored/cleared, shared VIN set/cleared |
| `BatteryReminder` | `BatteryReminderManager` (app) | BG task scheduled/fired, battery check outcome |

Conventions: every new intent `perform()` must create `let log = FleetIntentLog(Self.self, vehicle: vehicle)` and wrap its body in `do { ... log.success(...) } catch { throw log.failure(error) }` (keeps `.result(...)` type inference inside `perform()`; a generic wrapper closure breaks it). Never log full VINs or tokens — use `FleetKitLog.vin(_:)` (last 6 chars) and mark interpolations `privacy: .public` deliberately. `Logger` calls inside a struct `init` must copy stored properties to locals first (escaping autoclosure cannot capture mutating `self`).

### Common pitfalls (from prior reviews)

- Forgetting `FleetTokenBridge.sync` after sign-in, vehicle change, or token replacement → Siri “not signed in” or wrong account.
- On sign-out, delete the provider's local and shared credentials, clear the selected VIN, and remove the outgoing account's system suggestions, index entries, and battery reminder.
- Broken FleetKit URLs via `appendingPathComponent`.
- More than 10 `AppShortcut` entries → compile error.
- `DriveEntityQuery.entities(for:)` must search **all** account vehicles, not only the default resolved vehicle.
- Duplicating intent types under `TeslaSiri/AppIntents/` — conflicts with `public` FleetKit types; keep bridge/shortcuts only in the app target.
- **Do not move `TeslaSiriShortcuts` (AppShortcutsProvider) into the FleetKit package.** The appintentsmetadataprocessor only extracts `autoShortcuts`/`autoShortcutProviderMangledName` when the provider is compiled in the app target; in the package, BOTH the app and extension end up with zero shortcuts metadata. Verified empirically (June 2026, Xcode 27 beta).
- `ENABLE_DEBUG_DYLIB` is set per-SDK on the TeslaSiri target in project.xcproj: `YES` base (required for Xcode Previews) but `NO` for `[sdk=iphoneos*]` — with the debug dylib the app code is in `TeslaSiri.debug.dylib` and App Intents/App Shortcuts metadata breaks on device debug runs. To render previews, switch the run destination to a simulator first.
- Build against an iOS destination (a simulator or "Any iOS Device"). The TeslaSiri target still lists `macosx`/`xros` in `SUPPORTED_PLATFORMS` from the project template, but its UI uses iOS-only SwiftUI APIs (`textInputAutocapitalization`, `Color(.systemGroupedBackground)`), so a "My Mac" build fails. Treat that as a known gap; don't edit around it as a regression.
- Schedule `BGAppRefreshTaskRequest`s with `try await BGTaskScheduler.shared.submitTaskRequest(_:)`. The synchronous `submit(_:)` is deprecated as of iOS 27.0 (`BatteryReminderManager.schedule()` is `async` for this reason).
- Known iOS 27 beta issue: `LNMetadataProviderErrorDomain 9004 "No app shortcuts provider mangled type name in bundle"` from `updateAppShortcutParameters()`, with the downstream fault `Provided AppIntent does not match an App Shortcut, SiriTipView will not display.` Ruled out empirically (June 2026, controlled probe experiments on device): NOT the debug dylib (persists with static binary), NOT package-located intents (a probe intent compiled directly into the app target still failed), NOT `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING` (failed with it NO), NOT MainActor default isolation (failed with `nonisolated` provider+intent), NOT stale install state (failed after `devicectl` uninstall + fresh install). `Metadata.appintents/extract.actionsdata` verifiably contains the provider mangled name, all actions, and 10 autoShortcuts every time. Conclusion: OS-side `linkd` registration failure for dev installs on this beta (simulators can't reproduce — `linkd` doesn't run there). Remedies: reboot the device (restarts `linkd`), check the Shortcuts app for the TeslaSiri section, file Apple Feedback with sysdiagnose if it persists. Do not restructure app/package code for this error.
- `TeslaSiriShortcuts` is declared `nonisolated` deliberately: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the AppIntents runtime reads `appShortcuts` from arbitrary contexts. Keep it that way.
- `FleetIntentClientTests` must stay `@Suite(.serialized)` — `MockURLProtocol` uses shared static responder state and Swift Testing runs suites in parallel by default. Prefer per-test header-keyed `URLProtocol` instances (as in `FleetSiriAIToolsTests`) for new test suites so they run safely in parallel.

### Validation checklist (FleetKit changes)

1. `DocumentationSearch` for any new App Intents API usage.
2. Add or update Swift Testing coverage in `FleetKit/Tests/FleetKitTests/` for new FleetKit models, clients, control helpers, intent metadata, `IndexedEntity` formatting/search attributes, Siri AI tools, and bundled `SKILL.md` skills.
3. For Siri/Shortcuts/Spotlight integration behavior that must run through the real App Intents stack, add AppIntentsTesting coverage in a UI testing target (`IntentDefinitions(bundleIdentifier:)`, entity queries, `spotlightQuery(_:)`, and `viewAnnotations()` as applicable). Keep those tests out-of-process; do not import app/FleetKit implementation types into the UI test target.
4. `XcodeRefreshCodeIssuesInFile` on edited Swift files.
5. Run the relevant Swift package tests (`swift test --package-path FleetKit`) and AppIntentsTesting/XCUITest suite when one exists.
6. `BuildProject` (catches shortcut count, `@Parameter` macro issues).
7. Manually verify token bridge call sites if touching auth, `FleetProviderTokenStore`, `AppRootView`, or `DashboardView`.

### Navigation handoff

`SendNavigationIntent` (`ConvenienceControlIntents.swift`) sends a destination to the car through Tessie's `share` command. The `destination` String parameter uses `inputConnectionBehavior: .connectToPreviousIntentResult` so Shortcuts can pipe output from a previous action into it. Tessie accepts an address, coordinates, or URL as the plain `value` query parameter; address form covers the Siri use case.
