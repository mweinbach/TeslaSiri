# Making an Intent Available to Siri as a Tool

**SDK Version:** iOS 27.3, macOS 27.3, visionOS 27.3. Unavailable on watchOS and tvOS.

A *tool intent* is an app intent that Siri's model may choose and fill to fulfill a request. You adopt it with one argument to the existing `@AppIntent` macro: `@AppIntent(.tool)`. Nothing else about the intent changes. Its `perform()`, parameters, and result stay as they are, and it keeps working in Shortcuts, Spotlight, and App Shortcuts.

Siri can call a tool intent when:

- the request names the app,
- the app is in the foreground,
- a Live Activity from the app is running, or
- an entity from the app has been retrieved from search.

Details of those four conditions:

- **Naming the app means its real name.** Use the app's display name (`CFBundleDisplayName`, or `CFBundleName`). In 27.3, `AppShortcut` app-name synonyms don't bring an app's tools into scope.
- **Foreground isn't exclusive.** On iPad, Mac, and iPhone Duo, two apps can be in the foreground at once. Siri considers the tools of both, so make each tool's description clear enough to win against another app's tools.
- **Retrieved from search includes onscreen and Spotlight entities.** In 27.3, a non-schema `IndexedEntity` found in Spotlight, or a non-schema entity annotated on screen, brings the app's tools and skills into context (see the app-intents-whats-new-27 skill's spotlight-indexing and onscreen-entities references).

To check that Siri discovered the app's tools and skills, ask Siri on the device: "What can I do with <app name>?" Users can ask the same thing, so it's also how they find what the app supports.

## Runtime limits

| Limit | What to do |
|---|---|
| **At most 40 tools per app.** | Start with the app's core actions and expand iteratively, measuring with the siri-evaluations skill. Every tool adds to what the model reads, which costs latency and makes tool selection less accurate, so don't expose dozens of overlapping tools just because you can. |
| **At most 30 tool calls for one request**, including requests that use a skill. | Don't make the model loop. If a person might act on many items ("favorite these 40 photos"), take a batch parameter. See "Acting on many entities at once." |
| **A tool call times out after about 30 seconds.** | Keep tools fast and granular. If an action genuinely takes longer, adopt `LongRunningIntent`, which adds system UI, progress reporting, and cancellation (the app-intents-whats-new-27 skill's execution-modes reference). |
| **Tools run through Private Cloud Compute.** The system prompt, tool metadata, arguments, and results are sent, end-to-end encrypted, to Private Cloud Compute. | Tools and skills don't run while the device is offline. Don't promise an offline Siri feature built on tools. |
| **No cross-device execution.** Siri on iPhone doesn't run an intent in the person's Mac app, and `ToolIntent` is unavailable on watchOS and tvOS. | Ship the intents natively on each platform where people should be able to use them. |

## Acting on many entities at once

Siri stops after 30 tool calls, and every call is a model round trip. A tool that takes a single entity forces the model to call it once per item, which is slow and fails for large selections. When a person might act on several items, take a batch:

- **`[PhotoEntity]`** when `perform()` needs the full entities.
- **`EntityCollection<PhotoEntity>`** when `perform()` only needs the identifiers, for example for one batch database update or REST call. The system then skips resolving every entity through the query before `perform()` runs. See the app-intents-whats-new-27 skill's entity-collection reference.

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppIntent(.tool)
struct FavoritePhotos {
    static let title: LocalizedStringResource = "Favorite Photos"
    static let description = IntentDescription("Marks one or more photos as favorites.")

    @Parameter(title: "Photos", description: "The photos to mark as favorites")
    var photos: EntityCollection<PhotoEntity>

    func perform() async throws -> some IntentResult {
        try await PhotoLibrary.shared.setFavorite(true, for: photos.identifiers)   // one batch call
        return .result()
    }
}
```

Call `resolvedEntities()` only if `perform()` later needs the full entities.

## Keeping background calls fast

When Siri calls a tool while the app isn't running, launching the whole app adds cold-start time to the request. Put the intents and the model code they call in a framework that both the app and an **App Intents extension** link. The system can then run the intent in whichever process is already running, or start the lighter extension when neither is. Leave `allowedExecutionTargets` at its default unless the intent needs a specific process (the app-intents-whats-new-27 skill's execution-modes reference).

## Adopting `@AppIntent(.tool)`

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppIntent(.tool)
struct AddToCart {
    static let title: LocalizedStringResource = "Add to Cart"
    static let description = IntentDescription(
        "Adds a product to the shopping cart."
    )

    @Parameter(title: "Item", description: "The product to add")
    var item: ProductEntity

    @Parameter(title: "Quantity", description: "How many to add", default: 1)
    var quantity: Int

    func perform() async throws -> some IntentResult {
        try await Cart.shared.add(item, quantity: quantity)
        return .result()
    }
}
```

The macro adds a `ToolIntent` conformance, which includes `AppIntent`, so you don't need to write `: AppIntent`. Writing the conformance yourself is equivalent:

```swift
struct AddToCart: AppIntent, ToolIntent { … }
```

Prefer the macro for new intents. It keeps the intent's roles and its schema, if any, in one attribute. For an intent that already ships on releases before 27.3, use a gated extension instead (see "Deployment target below 27.3"). `ToolIntent` has no requirements beyond those of `AppIntent`.

## Writing metadata for the model

Siri's model decides when to call the tool and how to fill it from the intent's metadata. The most important parts are:

- the intent's `title` and `description`
- each parameter's `title` and `description`

Write them for someone who has never seen the app:

- **The intent's description says what it does and what it affects.** Use "Adds a product to the shopping cart," not "Cart action."
- **Add search keywords for words people use that the title and description don't.** Siri also uses the description's `searchKeywords` to retrieve the right tool, for example `IntentDescription("Adds a product to the shopping cart.", searchKeywords: ["basket", "buy"])`. Use words a person would say, not internal terms.
- **Each parameter description says what the value means and its format.** Use "The departure date, in the traveler's local time zone," or "Duration in minutes." Don't just repeat the title.
- **Make every action of a tool clear.** A tool can cover several closely related actions with a mode parameter, for example `action: add | remove`, when they work on the same kind of value. Make the mode an `AppEnum`, and describe each case so the model knows what it does. If the actions take different parameters, or the tool needs a skill to explain which combination does what, separate tools are usually clearer.
- **Similar intents are told apart in their descriptions.** If `Add to Cart` and `Add to Wish List` both exist, each description should make clear which one applies.
- **Add a parameter description when it says more than the title.** Leave it out when the title says everything, such as "Quantity" for an `Int`.

- **Group many parameters.** A tool with a long list of parameters, especially required ones, is hard for the model to fill, and the Siri Integration Advisor warns about it. Group related values into a generable entity (see `generable-entities.md`).
- **Localize it.** Siri reads the tool's `title` and `description` in the device's system language. Localize titles, descriptions, parameter descriptions, and `searchKeywords` for every language the app ships, which helps tool selection for non-English requests and the Shortcuts UI alike.

This is the same text that Shortcuts and Spotlight show, so improving it helps everywhere. There's no separate model-only description. Don't invent one.

**Freeform text is fine to forward.** A tool can take a plain `String` the model writes from the request, such as "summarize this note in a friendly tone", and pass it to the app's own on-device model in `perform()`, for example a Foundation Models `LanguageModelSession`. Describe what the text should contain, and keep the tool within the 30-second limit.

## What Siri sees from a tool's output

The model reads what a tool returns and what it throws, and uses both to decide what to do next and what to tell the person.

- **Return a value when a later step needs one.** For example, a tool that places an order should return the order, `some ReturnsValue<OrderEntity>`, so the model can pass it to a tool that tracks the delivery. A tool that returns only `.result()` gives the model nothing to continue with.
- **Throw errors whose messages say what went wrong and what would fix it.** Siri sees the error. "That store doesn't deliver on Sundays" lets the model ask for another day. A generic "Operation failed" doesn't. Only errors that conform to `CustomLocalizedStringResourceConvertible` carry a real message, so conform the app's error type to it. See the app-intents-specialist skill's results-and-errors reference.

## Choosing which intents become tools

Make an intent a tool when a person would reasonably ask Siri to do it. That **includes** actions with real-world effects, like buying, booking, sending, or deleting. These are often the most valuable tools. For them:

- Keep, or add, the confirmation the intent would show anywhere else, for example `requestConfirmation` before charging the person.
- For a new intent, confirm before anything that deletes or overwrites the person's data, for example replacing a meal that's already planned. Don't confirm additions that are easy to undo.
- Make the description state the effect plainly, for example "Places the order and charges the saved payment method."

**Tools are always available.** A tool can't be enabled or disabled, so the model can find and call it in any of the situations listed at the top of this reference, such as when the request names the app, whatever the app is doing. Don't make an intent a tool if it only works while the app is running, or only when the app is in a particular UI state, such as a specific screen being open. A tool should work whenever it's called, or throw a clear error that says what the person needs to do.

## Entity parameters the model finds through a query

For a parameter whose type is an app-owned (non-transient) entity, the model gets a value from the app rather than writing one.

**Don't write tools that search for the app's entities.** A "search recipes" or "find products" tool that takes criteria and returns entities duplicates what Siri already does. Siri finds entities itself, through Spotlight and the entity's query, using the mechanisms below. Make the entities findable, and write tools that **act on** an entity and take it as a parameter, like "add this recipe's ingredients to the shopping list." This applies to large catalogs too: index their items so they're entities Siri can find, not results of a search tool. The one exception is a live remote catalog whose items don't exist on the device until the server is asked (see "Remote catalogs that can't be indexed").

- **The entity's query must implement `entities(for:)`** to look entities up by identifier. Every non-transient entity a tool uses needs it.
- **Give Siri a way to find candidates.** Siri finds entities from what the person said in two ways. **Prefer `IndexedEntity` wherever the entities can be indexed.** Siri looks them up in Spotlight without launching the app, which is faster and cheaper. It also lets Siri find an entity when the request doesn't name the app. For privacy, Siri sends a query to the app only when the person names the app. `EnumerableEntityQuery` always runs the app's code. Use it for small sets that can't be indexed.

| Mechanism | Use when | What to implement |
|---|---|---|
| `IndexedEntity` | The entities can be indexed in Spotlight. This is the preferred mechanism, and the right one for large or growing sets like documents, recipes, products, or contacts. Lookups don't launch the app. | Conform the entity to `IndexedEntity`, give its searchable properties Spotlight keys such as `@Property(title: "Name", indexingKey: \.displayName)`, and index the entities with Core Spotlight. Indexing is covered in the app-intents-whats-new-27 skill's spotlight-indexing reference. |
| `EnumerableEntityQuery` | The full set is small and bounded, like the person's lists or courses, and indexing doesn't fit. Every lookup runs the app's `allEntities()`. | Conform the query to `EnumerableEntityQuery` and return every entity from `allEntities()`. |
| `DynamicOptionsProvider` | A non-entity parameter, such as a `String` or `Int`, whose valid values are a small set known only at run time. | Pass `optionsProvider:` to the `@Parameter` and return the options from `results()`. Prefer `IndexedEntity` when the values are things the app stores. |

  **For tool intents, Siri doesn't use `suggestedEntities()`, `EntityStringQuery`'s `entities(matching:)`, or `EntityPropertyQuery`.** Siri doesn't call `suggestedEntities()` ahead of time, when it offers the app's tools to the model, so suggested entities aren't surfaced. Keep them if the app already has them, for example for Shortcuts, but don't add them to make an entity findable for a tool.
- **The model reads each entity's `displayRepresentation`** to tell results apart, pick one, or ask the person which one they meant. Make it specific: a title that names the thing, and a subtitle that tells similar ones apart, such as `DisplayRepresentation(title: "\(name)", subtitle: "\(neighborhood)")`. Don't show an internal identifier, such as a UUID or a database ID.
- **Expose and describe the properties Siri needs**, and hide sensitive ones with `visibility: .internal`. The model reads the properties of every entity it sees, whether as a parameter or in a result. See `entity-properties.md`.

### Remote catalogs that can't be indexed

The no-search-tools rule assumes the entities exist on the device, so Siri can find them in Spotlight or through `allEntities()`. Some catalogs can't work that way. The person's items exist only on a server until the app asks for them, and the set is too large or changes too fast to index: live flight availability, hotel inventory, or a store with millions of products. In 27.3, Siri doesn't call `entities(matching:)` or `EntityPropertyQuery` for tool intents, so the entity's query can't do the search either.

For that case only, a lookup tool is the right shape:

- **The criteria are a generable entity** the model writes from the request, such as a `FlightSearch` with origin, destination, and date. Describe each property's format precisely (see `generable-entities.md` and `entity-properties.md`).
- **It returns the matches as app-owned entities**, `some ReturnsValue<[FlightEntity]>`, so the next tool, such as "Book Flight", takes one as its parameter. Give them a specific `displayRepresentation` so the model can ask the person which one they meant.
- **Its title and description say it looks up live results from the service**, so it doesn't compete with Siri's own search of the device.
- **Index what you can.** Anything the person already has, such as their bookings, saved products, or favorite stores, is still an `IndexedEntity` and still not found through a tool.

Don't use this exception for data that lives on the device, for data the app could index, or for small sets that `EnumerableEntityQuery` covers.

## Intents that conform to a schema

Add `.tool` to the `@AppIntent(schema:)` the intent already uses. The result does everything `@AppIntent(schema:)` does, including the schema's conformances and default `@Parameter` attributes, and also adds `ToolIntent`:

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppIntent(.tool, schema: .journal.createEntry)
struct CreateEntryIntent {
    var title: String?
    var message: AttributedString
    var mediaItems: [IntentFile]
    var entryDate: Date?
    var location: CLPlacemark?

    // The schema requires returning an entity that adopts
    // @AppEntity(schema: .journal.entry).
    func perform() async throws -> some ReturnsValue<JournalEntryEntity> { … }
}
```

Adding `.tool` doesn't relax the schema's contract. The intent's parameters and result must still match the schema, and the build reports any mismatch, for example `requires that 'perform()' must return @AppEntity(schema: .journal.entry)`.

**Siri reads the custom metadata of these intents.** For a primary-domain schema intent, Siri ignores custom titles and descriptions and uses the schema's meaning. For an `@AppIntent(.tool, schema:)` intent, it reads the intent's own `title` and `description` like any other tool, so write them as carefully.

**Only Shortcuts-only schema domains can be tools:** `books`, `browser`, `journal`, `presentation`, `reader`, `spreadsheet`, `whiteboard`, and `wordProcessor`. Intents in the Apple Intelligence + Siri primary domains (`audio`, `calendar`, `camera`, `clock`, `files`, `mail`, `maps`, `messages`, `notes`, `phone`, `photos`, `reminders`, `system`) are already handled by Siri. Combining one with `ToolIntent` is a build error, however it's written:

```swift
@AppIntent(.tool, schema: .messages.sendMessage)
struct SendMessageIntent { … }
// ❌ error: 'ToolIntent' can't be adopted by an intent that conforms to
//    '.messages.sendMessage' because the schema is in a primary domain

@AppIntent(schema: .messages.sendMessage)
struct SendMessageIntent: ToolIntent { … }    // ❌ same error

extension SendMessageIntent: ToolIntent {}    // ❌ same error
```

The fix is to remove `.tool` or `ToolIntent`. The schema adoption already makes the intent available to Siri.

**Apps in a primary domain still add tools.** The build error applies only to the schema intent itself. A calendar, notes, reminders, or navigation app should add separate `@AppIntent(.tool)` intents for the app-specific actions its schema doesn't cover, such as "Share Event with Team" in a calendar app. These tools can take the schema entities, like `@AppEntity(schema: .calendar.event)` types, as parameters. Don't write a custom tool that does what one of the schema intents already does. It competes with the schema intent for the same requests.

**Donate the schema intents.** Requests in a primary domain often don't name an app, so Siri picks one, and it falls back to Apple's app for the domain. When the person does a schema action in the app, donate it with `IntentDonationManager.shared.donate(intent:)` so Siri learns that they use this app for it (the app-intents-specialist skill's donation reference).

## Trait syntax

`AppIntentTraits` is a set. Pass one trait or a list literal:

```swift
@AppIntent(.tool)
@AppIntent([.tool])
@AppIntent(.tool, schema: .journal.createEntry)
@AppIntent([.tool], schema: .journal.createEntry)
```

The macro reads the traits as written in the source:

| Written | Result |
|---|---|
| A trait in a variable, or computed with `union(_:)` | Build error. Write the traits inline. |
| The same trait twice, e.g. `[.tool, .tool]` | Build error |
| `@AppIntent([])` with no schema | Build error |
| `@AppIntent([], schema: …)` | Warning, no effect. Use `@AppIntent(schema:)`. |

## Deployment target below 27.3

The macro uses the availability declared on the type, so which form to use depends on whether the intent already exists on earlier releases:

| Situation | Form |
|---|---|
| The intent already ships, or must stay available, on releases before 27.3. This is the usual case when adopting in an existing app. | Leave the intent as is, and add the conformance in a gated extension. |
| The intent is new and only needs to exist on 27.3 and later | `@AppIntent(.tool)` with `@available` on the type |

**Existing intent.** Don't put `@available(iOS 27.3, …)` on an intent that already ships. That would remove it from Shortcuts, Spotlight, and App Shortcuts on earlier releases.

```swift
struct AddToCart: AppIntent { … }       // unchanged, still available on earlier releases

@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
extension AddToCart: ToolIntent {}
```

**New intent, 27.3 and later only:**

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppIntent(.tool)
struct AddToCart { … }
```

**Targets that build for watchOS or tvOS.** `ToolIntent` is unavailable on those platforms, so `@available(…, *)` alone isn't enough. Wrap the conformance in `#if !os(watchOS) && !os(tvOS)`. Check the target's supported platforms to decide whether you need it.

## Common pitfalls

- **Adding `.tool` without fixing the metadata.** A tool with the title "Run" and no description is effectively invisible to the model, or gets called for the wrong requests. Review the title and descriptions in the same change.
- **Overlapping with what Siri already does.** A tool that duplicates a built-in Siri feature or a primary-domain schema, such as setting a timer, sending a message, playing music, or controlling home accessories, competes with the system for those requests. Adopt the schema if one fits (see "Intents that conform to a schema"). Otherwise make the title and description say what's specific to the app. The analyzer reports close matches with system schemas as `SMA701` (see `metadata-analyzer.md`).
- **A mode parameter the model can't interpret.** If the cases of a mode or action parameter aren't described, or the right combination of mode and other parameters isn't clear from the metadata, the model guesses. Describe every case, or split the tool.
- **Leaving out the actions people most want.** Purchases, bookings, and other actions with effects should be tools. Keep their confirmation, but don't exclude them.
- **Tools that depend on the app's state.** Tools are always callable whenever Siri can reach the app. A tool that only works while the app is running, or on a particular screen, fails for most requests.
- **Returning nothing useful.** A tool that returns only `.result()`, or throws a generic error, leaves the model nothing to act on.
- **Adding `.tool` to a primary-domain schema intent.** It's a build error, and Siri already handles that intent. See above.
- **Inventing a model-only description or tool name.** No such API exists.
- **Referring to tools by their Swift type name in skills or descriptions.** Write "the Add to Cart tool", using the title in natural language, not `AddToCart`. Within a tool's own description, write "this tool". How Siri represents tool names internally isn't part of the API and can change.
- **Dropping the feature for an older deployment target.** Gate it with `@available` instead.
- **A query Siri can't find candidates with.** A query that only implements `entities(for:)` lets Siri resolve identifiers it already has, but not find a store from "the Market Street store." Add `IndexedEntity`, or `EnumerableEntityQuery` for a small set.
- **A vague or identifier-only `displayRepresentation`.** The model reads it to choose between results. "Store 4417" can't be told apart from other stores. "Market Street", with the subtitle "San Francisco", can.
- **Writing a search or find tool.** Siri finds entities itself through Spotlight and queries. Make the entities findable, and take them as parameters instead. The only exception is a live remote catalog (see "Remote catalogs that can't be indexed").
- **A single-item tool for a multi-item task.** Siri stops after 30 tool calls. Take `[Entity]` or `EntityCollection<Entity>` instead.
- **Too many tools.** The limit is 40, and well before that, overlapping tools slow Siri down and confuse tool selection. Start with the core actions.
- **Slow tools.** A call that takes more than about 30 seconds times out. Split it, or adopt `LongRunningIntent`.
- **Expecting tools offline or across devices.** Tools run through Private Cloud Compute and need a network connection, and they run only on the device where Siri was asked.
- **Unlocalized metadata.** Siri reads titles and descriptions in the device's language. Untranslated text hurts tool selection there.
- **Relying on `AppShortcut` app-name synonyms.** They don't bring the app's tools into scope in 27.3. Only the app's name does.
