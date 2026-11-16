# Wattie

Wattie is an independent SwiftUI app for viewing and controlling Tesla vehicles through Tessie or Teslascope. It combines a vehicle dashboard, drive and charging history, and vehicle controls in Siri and Shortcuts. The Xcode project and app target are named `TeslaSiri`.

The 3D showroom started as an experiment to see how closely RealityKit could reproduce the vehicle rendering in Tesla's Android app. The extracted models were converted to USD and animated using vehicle telemetry. The same renderer powers the showroom and replays recorded drives.

## Run locally

1. Open [`TeslaSiri.xcodeproj`](TeslaSiri.xcodeproj/) in Xcode 27.3 or later and select the `TeslaSiri` scheme and an iOS 27.3 or later simulator or device. For device builds, set your signing team and bundle IDs on the app and its extension. Use matching App Group and keychain access group entitlements in both targets, and update the App Group ID in [`FleetKitConfig.swift`](FleetKit/Sources/FleetKit/FleetKitConfig.swift).
2. To explore with sample data, choose **Demo Car** under **Diagnostics → Siri & Command Sandbox**.
3. For live data, open **Settings** in Wattie, select **Tessie** or **Teslascope**, and paste that provider’s access token. Wattie remembers each connection separately in Keychain. Existing installations keep their Tessie connection.
   - **Tessie** issues access tokens in its Developer settings. [Tessie Developer settings](https://dash.tessie.com/settings/api)
   - **Teslascope** issues personal access tokens under **Developers → Applications**. Give the token `tesla-accounts` for vehicle discovery and `vehicles` for data. Add `controls` to send supported commands on a premium subscription. [Teslascope authentication](https://teslascope.com/developers/documentation) · [Teslascope command requirements](https://teslascope.com/developers/documentation/vehicles-tesla-api)

## Project layout

- [`TeslaSiri/`](TeslaSiri/) contains the SwiftUI app, Fleet data adapters, and RealityKit showroom and drive replay.
- [`FleetKit/`](FleetKit/) contains the App Intents, Shortcuts and Spotlight integration, extension-safe provider clients, and Swift package tests.
- [`TeslaSiriAppIntents/`](TeslaSiriAppIntents/) hosts the App Intents extension.
- [`TeslaVehicleKit/`](TeslaVehicleKit/) contains the RealityKit loader and bundles the converted Fleet resources.

See [AGENTS.md](AGENTS.md) for development and validation conventions. Keep provider tokens, raw vehicle exports, and signing files out of commits.

## License

The [MIT License](LICENSE) applies to the project-authored code and documentation. Tesla retains its rights to the vehicle models and related assets in the RealityKit conversions. The [third-party notices](THIRD_PARTY_NOTICES.md) identify the assets and marks excluded from the MIT grant.
