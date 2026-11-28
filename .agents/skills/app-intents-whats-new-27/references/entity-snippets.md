# Entity Snippets
**SDK Version:** 27.3 and later (declared `@available(anyAppleOS 27.3, *)`)

If the user's deployment target is below 27.3, the APIs in this reference (`SnippetRepresentableEntity`, `EntitySnippetContent`, `EntitySnippetContentBuilder`, `CardSnippet`, `CardSnippetFamily`, and `CardSnippetContext.family`) require availability gating. See "Deployment target below 27.3" below.

An *entity snippet* is the app's own SwiftUI card for an `AppEntity`. When Siri's model shows one of the app's entities in a response, for example an event it found or the order a tool returned, the system can draw the app's card instead of a generic one built from the entity's `displayRepresentation`. Running example: **CometCal**, whose `EventEntity` is an `IndexedEntity` with `title`, `startDate`, and `calendarName`.

This is a different surface from an intent's **result snippet** (`SnippetIntent` / `.result(view:)`, see `interactive-snippets.md`), which belongs to one run of one intent. An entity snippet belongs to the entity type, so every place Siri shows that entity uses it. It works for schema and non-schema entities.

## Adopting `SnippetRepresentableEntity`

Conform the entity and return its card from the static `snippet` property. `snippet` is built with `EntitySnippetContentBuilder`, which the protocol requirement applies for you. Today's one content type is `CardSnippet`, whose closure receives the entity and a `CardSnippetContext` and returns a SwiftUI view:

```swift
import AppIntents
import SwiftUI

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension EventEntity: SnippetRepresentableEntity {
    static var snippet: some EntitySnippetContent<EventEntity> {
        CardSnippet(supportedFamilies: [.standard]) { event, context in
            EventCard(event: event)
        }
    }
}

struct EventCard: View {
    let event: EventEntity

    var body: some View {
        VStack(alignment: .leading) {
            Text(event.title).font(.headline)
            Text(event.startDate, format: .dateTime.weekday().hour().minute())
            Text(event.calendarName).foregroundStyle(.secondary)
        }
    }
}
```

- **`supportedFamilies:`** lists the card families the view can draw. `CardSnippetFamily.standard` is the one family the 27.3 SDK declares. If a later SDK adds others, read `context.family` in the closure to lay the card out for the family the system asked for.
- **The closure runs on the main actor.** It receives the already-resolved entity, so draw from the entity's own values. Don't fetch or mutate app data in the view.
- **Keep the card read-only and self-contained.** It's a picture of the entity, not a screen of the app. To let the person act on the entity, expose tools that take it as a parameter (the siri-app-integration skill's tool-intents reference).
- **Keep `displayRepresentation` specific anyway.** Siri's model reads the display representation and the entity's properties, not the card, to choose between entities and answer questions about them.

Only the members listed here are public. Don't call `EntitySnippetContent`'s underscored requirement or use the `_EntitySnippetContent_Input` / `_Output` types.

## Shipping

Apple's 27.3 labs said that an app can ship entity snippets in an App Store build as soon as 27.3 is released. That's unlike tool intents and App Skills, whose Siri integration was limited to development and TestFlight builds during the preview, with App Store support planned for the spring. Check the current release notes before promising a date.

## Deployment target below 27.3

Add the conformance in a gated extension, as above, and leave the entity itself at its existing availability. Don't put `@available(… 27.3, …)` on an entity type that already ships, because that removes it from Shortcuts and Spotlight on earlier releases.

```swift
struct EventEntity: AppEntity, IndexedEntity { … }   // unchanged

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension EventEntity: SnippetRepresentableEntity { … }
```

## Availability summary

| API | Availability |
|---|---|
| `SnippetRepresentableEntity`, `EntitySnippetContent`, `EntitySnippetContentBuilder` (AppIntents) | `anyAppleOS 27.3` |
| `CardSnippet`, `CardSnippetFamily`, `CardSnippetContext.family` (AppIntents with SwiftUI) | `anyAppleOS 27.3` |
