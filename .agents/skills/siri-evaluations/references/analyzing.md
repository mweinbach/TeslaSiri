# Analyze: why scenarios failed, and what to fix

Read a Siri evaluation report and, for each unsatisfied expectation, identify what Siri actually
observed (different intent called, no intent called, a parameter missing, other entities found, an
unexpected clarification, a forbidden intent called, a reply that didn't match), then decide, based
on the goal of the scenario, whether the fix belongs in the app's App Intents code or in the scenario
itself.

## Guardrails

- Diagnose from the report, not from the test's pass/fail. Each claim about what Siri did should quote
  a check row or a transcript line from the report.
- Decide first whether the failure is in the **environment**, the **app**, or the **test**. Only app
  failures lead to App Intents changes. Don't edit intents to compensate for an incorrect expectation
  or a device that was not ready.
- Never make a scenario pass by loosening its expectation unless the expectation doesn't match the
  goal of the scenario. Say so explicitly when you do.
- Siri is nondeterministic. One failure out of several paraphrases is a signal to investigate, not
  proof. A failure that repeats across reruns and paraphrases may be systematic.
- After changes to App Intents code, the app must be rebuilt, reinstalled, and launched before
  rerunning (see references/running.md).

## Reading the report

Xcode shows each scenario as a table: **Key** (what is checked), **Subject** (what Siri observed),
**Expected** (what the scenario asked for), and **Issues**, which flags every row where Subject and
Expected differ. Each scenario has these sections:

- **Diagnostics**: context for the run rather than checks: how many of the app's entities Spotlight
  had indexed, how many turns completed, and anything Siri did that could not be read. A check that
  depends on something that could not be read cannot be trusted.
- **Scenario**: the scenario's whole-conversation expectations, if it has any.
- **Turn 1, Turn 2, …**: the user's utterance, a group of rows for each expectation written for the
  turn, then Siri's response.

Each group starts with a row for what the expectation checks (an intent call, an entity, the reply, or
an App Skill), followed by a row for each parameter or property it constrains. Subject shows what Siri
actually did: the call it made and its arguments, the entities it found or saw on screen, its reply, or
the skills it loaded. A row that could not be checked, because the call never ran or what Siri did
could not be read, is neither a pass nor a failure; look at the turn's earlier rows and the
Diagnostics for the reason.

A metric's rationale only counts the checks that held. The flagged rows show which ones failed.

## Workflow

1. **Get the report.** Ask for it or export it.
2. **Rule out the environment and the build.** If every scenario fails the same way, the Diagnostics
   show fewer completed turns than the scenario has, or the Spotlight index is empty, stop and work
   through references/running.md → "When the run doesn't get to grading" instead. Also check:
   - **Was the device online?** Tools and App Skills run through Private Cloud Compute. An offline
     device, or one that couldn't reach it, fails every tool and skill scenario.
   - **Did the tool ship?** If Siri never calls an intent, or says the app doesn't support the
     request, run `xcrun sirimetadataanalyzer` on the built app (the siri-app-integration skill's
     metadata-analyzer reference) and confirm the intent is exported as a tool. Target membership,
     an `@available` later than the device's OS, or a build error in another App Intents type can
     leave it out.
   - **Is it a deterministic bug?** If Siri called the right intent with the right arguments and the
     result or error is wrong, the bug is in `perform()` or an `EntityQuery`. Reproduce it with
     `AppIntentsTesting` (the app-intents-whats-new-27 skill's testing reference) rather than with
     more Siri runs.
3. **For each failing scenario**, walk the failing check rows in turn order. The first failure in a
   turn usually explains the rest (an intent that wasn't called leaves its parameter rows unchecked).
4. **Read the app code the failure points at**: the intent's `title`, `description`, `@Parameter`
   declarations, `parameterSummary`, `perform()` return type and dialog; the entity's
   `displayRepresentation`, `EntityQuery`, and indexing. Read the scenario too; confirm the
   expectation matches what the utterance actually asks for. Causes that are easy to miss:
   - **Missing `searchKeywords`.** Siri misses a tool when the person used a synonym or verb that
     isn't in its title or description. Check `IntentDescription("…", searchKeywords: […])`.
   - **Overlapping tools.** Another `.tool` intent with a similar description won the request. Read
     every tool's description, not just the expected one. The more tools the app exposes (up to 40),
     the more this happens.
   - **Too many parameters.** A tool with many flat parameters, especially required ones, gets
     filled wrong. Group related values into an `@AppEntity(.generable)` (the siri-app-integration
     skill's generable-entities reference).
   - **The tool wasn't in scope.** For an app-less utterance, none of the four conditions that bring
     an app's tools into scope held (named app, foreground, Live Activity, entity from search). Also
     check whether the utterance used an `AppShortcut` app-name synonym instead of the app's name,
     which doesn't work for tools in 27.3, or whether another foreground app's tools competed on iPad
     or Mac.
   - **A primary-domain request went to Apple's app.** For a schema intent, check whether the app
     donates the action with `IntentDonationManager` and whether the test device has any history of
     the person using the app for it.
   - **The 30-call cap or the 30-second timeout.** A multi-item request that stops partway usually
     means Siri looped over a single-item tool. The fix is a batch parameter (`[Entity]` or
     `EntityCollection`). A tool that runs out of time needs to be faster or adopt
     `LongRunningIntent`.
   - **Language mismatch.** The device's Siri language has no localized `title` or `description` in
     the app bundle.
5. **Write up each failing scenario** in this shape:

   > **"In CometCal, create an event called Comet Watch tomorrow at 3PM"** — ✗ Turn 1, `title` of
   > `CreateEventIntent`: Siri set "Comet Watch tomorrow at 3PM", the scenario expected "Comet Watch"
   > **What happened:** Siri called `CreateEventIntent(title: "Comet Watch tomorrow at 3PM")` — the
   > date and time were folded into the title.
   > **Why:** `title`'s parameter has no description, and the intent has no `date` parameter Siri
   > could put "tomorrow at 3PM" into. *(app — systematic across 3 paraphrases)*
   > **Fix:** `CreateEventIntent.swift:14` — add a description to `title` ("The event's name only,
   > without its date or time") and a `startDate` parameter. Diff below.

   Group scenarios that fail for the same reason and give the fix once.
6. **Rerun** the failing scenarios after the developer applies fixes, and compare the report with the
   previous one. If a fix didn't move the metric, say so and revisit the diagnosis.
