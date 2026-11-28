import AppIntents

/// Declares the App Intents defined in this Swift package so that targets which
/// link `FleetKit` can surface them to the system. The app references this type
/// from `includedPackages`; the App Intents extension links `FleetKit` statically
/// with an empty `AppIntentsPackage` conformance.
public struct FleetKitPackage: AppIntentsPackage {}
