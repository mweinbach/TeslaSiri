import AppIntents
import FleetKit

/// `FleetKit` is statically linked into this extension, so its App Intents
/// metadata is merged directly into the extension bundle without listing it in
/// `includedPackages`.
extension TeslaSiriAppIntentsExtension: AppIntentsPackage {}
