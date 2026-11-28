# Retiring Intents and Protecting Sensitive Ones

## Retire an intent with `DeprecatedAppIntent` — don't delete it

Saved shortcuts replay an intent by its type name, so deleting or renaming a shipped intent breaks every shortcut that uses it. When a newer intent replaces an old one — for example, intents migrated from SiriKit being replaced by tool intents — keep the old type and conform it to `DeprecatedAppIntent` (iOS 17.0). The system stops offering it in the Shortcuts action list and search, while the person's existing shortcuts keep running it.

```swift
// AVOID: deleting the old intent. Every saved shortcut that runs it breaks.

// PREFER: keep it, mark it deprecated, and point at the replacement.
struct LogWorkoutLegacyIntent: AppIntent, DeprecatedAppIntent {
    static let title: LocalizedStringResource = "Log Workout"
    static var deprecation: IntentDeprecation<LogWorkoutIntent> {
        IntentDeprecation(replacedBy: LogWorkoutIntent.self)
    }

    func perform() async throws -> some IntentResult { /* still works */ .result() }
}
```

`IntentDeprecation` takes a `message:`, a `replacedBy:` intent type, or both. With no replacement, use `IntentDeprecation(message:)`; its generic argument is then `Never`, which is also the protocol's default. Keep the deprecated intent's `perform()` working — deprecation only hides it from new use.

## Require unlock with `authenticationPolicy`

`static var authenticationPolicy: IntentAuthenticationPolicy` sets what the device must do before the system runs an intent, for example from the Lock Screen or through Siri on a locked device:

| Case | Meaning |
|---|---|
| `.alwaysAllowed` | Runs without unlocking. |
| `.requiresAuthentication` | The person must unlock the device first. |
| `.requiresLocalDeviceAuthentication` | The person must authenticate on this device itself, not through a connected device. |

Set it on the intent for actions that read or change something sensitive — moving money, revealing a balance, deleting data. In iOS 27.3, the same policy is also available on an `AppEntity` (`static var authenticationPolicy`) and on an individual entity property (`@Property(…, authenticationPolicy:)`), so requests that touch only non-sensitive values still work from the Lock Screen; see the `siri-app-integration` skill's entity-properties reference.

`authenticationPolicy` is not a way to hide a value from Siri. A protected property is still readable after unlock. To keep a value from Siri and Shortcuts entirely, use `visibility: .internal` on the property (iOS 27.3), or don't expose it.
