# Custom animation state and interruption

## Separate intent, phase, and observed geometry

“Expanded” can mean several different things:

| State | Example | Meaning |
| --- | --- | --- |
| Desired state | `.expanded` | What the most recent request wants |
| Model/layout destination | `isCollapsed == false` | Where the native owner is going; may update immediately |
| Presentation/observed value | reveal progress `0.37` | Where the UI currently appears, in a defined coordinate/measurement system |
| Lifecycle phase | `.moving(toward: .expanded)` | Whether app-owned work is in progress |
| Completion status | settled or logically complete | A specifically chosen engine event |
| Attachment | detached / attached to window A | Whether the visual owner can be updated at all |

A Boolean is useful for intent. It is not a sample of an in-flight animation. Toggling a Boolean and inspecting it 100 milliseconds later does not measure the animation.

The [Commander workspace guide](../../../../docs/workspace-chrome.md) documents a native driver with a geometry follower. Use the project guide and source for its current state and measurement choices.

## Choose between a driver and a follower

### Driver: the app owns interpolation

Use an explicit state model when the app owns timing, gestures, a reveal, or a sequence. A useful conceptual state machine is:

```text
detached
  └─ attach at an established endpoint ─→ settled(endpoint)

settled(A)
  └─ request B ─→ moving(toward: B, revision: n)

moving(toward: B, revision: n)
  ├─ request A ─→ moving(toward: A, revision: n+1)
  ├─ finish n, still current ─→ settled(B)
  ├─ finish older revision ─→ ignore
  ├─ interrupt ─→ interrupted; invalidate outstanding completion
  └─ detach ─→ detached; invalidate outstanding completion

interrupted
  └─ request any endpoint, including B again ─→ moving(new revision)
```

[MotionRequestState.swift](../examples/MotionRequestState.swift) implements the bookkeeping independently of an animation engine. Its `observe` method records measured progress without pretending that an endpoint observation is an engine completion. Its `finish` method is called only when the chosen completion contract has actually been satisfied.

Call `interrupt()` before cancelling or holding the owning engine so a cancellation callback cannot finish the current request. Then preserve the actual displayed position using that engine's supported mechanism. The state object alone cannot pause an animation. An interrupted request can resume toward the same endpoint; a repeated request to an already moving/settled endpoint is a no-op.

This example models semantic endpoints, not arbitrary coordinate targets. If the same semantic endpoint acquires new geometry after a resize, update the owning layout appropriately or include that geometry in a more specific request model. Do not suppress a necessary layout change merely because its endpoint name is unchanged.

### Follower: another owner already animates

Observe geometry and map it directly. A follower should not:

- run its own `0.3`-second timer because the driver's animation looks approximately that long;
- animate every incoming geometry sample with another spring;
- derive presentation progress from the target Boolean;
- restart on unrelated representable updates;
- retain a delayed target coordinate that can be obsolete after reversal.

A follower's direct geometry writes can be intentional: interpolating already-interpolated samples introduces lag and mismatched settling. The [Commander guide](../../../../docs/workspace-chrome.md) shows that separation in a native split.

## One property, one owner

Define ownership at property granularity rather than just view granularity:

```text
native split:      pane geometry and reveal timing
accessory owner:   outer glass x/y from measured reveal
glass framework:   native material and interaction response
button:           action, focus, accessibility, symbol
```

These can coexist because they control different responsibilities. Two systems both changing outer `frame.origin.x`, a constraint constant and `frame` competing, or a press effect changing the same translation as sidebar travel are conflicts.

For a future hover/press emphasis, use a separate visual parameter or an explicitly owned inner wrapper. Verify that it does not fight `effectIsInteractive` before adding another scale/deformation effect.

## Retargeting and continuity

- **Position continuity (C0):** no jump in the visible value when the target changes.
- **Velocity continuity (C1):** no abrupt change in travel velocity at the handoff.
- Matching duration alone establishes neither.

A new basic animation that starts from `presentation()?.position` can preserve position while resetting velocity. A correctly retargetable spring can preserve more of the motion's state. Choose the behavior required by the interaction and the owning engine.

For a geometry follower, a continuous mapping of the driver's actual geometry preserves the driver's positional behavior without inventing a second clock. Clamps, piecewise anchors, changing travel distance, or delayed samples can still introduce a plateau or discontinuity. Test these at narrow widths and during reversal.

The original native toggle's approximately `max(trafficLightLimit, sidebarTrailingEdge - inset)` path explains why identity could stay stable while the control seemed to stop or switch anchors. A stable object is necessary for persistent interaction state, but does not prove a continuous path.

## Completion and cancellation

Before starting app-owned animation:

1. Record the new desired state.
2. Increment/capture a request revision.
3. Establish starting layout or presentation as required by the engine.
4. Register the completion only after the bookkeeping is ready.

On completion, re-check the owner, attachment, desired state, and revision before hiding/removing a view, transferring focus, or marking it settled.

Reasons a completion can be misleading:

- an earlier request was reversed;
- an animation was cancelled or replaced;
- there were no animatable changes, so completion ran immediately;
- Reduce Motion selected an immediate path;
- a view disappeared or moved to another window;
- a spring is logically complete but its visual tail is still being removed.

SwiftUI completion criteria such as `.logicallyComplete` and `.removed` express different boundaries. Name the state accordingly. Use `.removed` when the caller needs that specific removal boundary; do not treat it as interchangeable with a semantic “operation accepted.” The standalone state example's `settled` naming assumes the caller uses a completion appropriate to that claim.

Classic `NSAnimationContext` completion is not proof that the latest request succeeded. See [the companion completion example](../../appkit-animation-control/examples/AppKitMotionExamples.swift) for revision-guarded cleanup and its documented main-thread assumption.

Do not put side effects in `animatableData` setters, shape paths, keyframe value builders, or timing callbacks. These are evaluation hooks, not lifecycle or business-action boundaries.

## Coalescing layout invalidations

Several geometry callbacks can occur while the native owner is still arranging ancestors. A pending-update flag can coalesce them:

```text
geometry callback
  ├─ update already queued? return
  └─ queue weak main-queue work
       ├─ clear queued flag
       ├─ validate current attachments
       ├─ read current geometry
       └─ place app-owned follower
```

Important details:

- Read the latest geometry **inside** the deferred work.
- Do not queue a sequence of captured historical frames.
- Reset the flag before the layout work, so a genuine new invalidation can schedule again.
- Guard the window relationship at execution time, not just scheduling time.
- Use a small size-change tolerance where a frame write itself may trigger another layout callback.
- Keep the callback MainActor-safe and weakly captured.

A before-draw sample can also catch ancestor movement that did not change a probe's local frame. The [Commander guide](../../../../docs/workspace-chrome.md) documents that project's sampling choices and source. This technique is not a universal compositor synchronization API.

## Gesture and interactive handoff

For a future app-owned drag/scrub control:

1. Capture the current displayed position at gesture start.
2. Follow input directly while dragging; avoid adding a spring to every pointer delta unless intentionally implementing a lagging interaction.
3. Define cancellation separately from a release toward an endpoint.
4. On release, choose the endpoint and velocity policy, then hand off to the selected engine.
5. Treat `@GestureState` reset as a separate transaction from the resting animation.
6. Continue to use revision checks if a later input can invalidate the release completion.

Use [springs and interaction](../../swiftui-animation-control/references/springs-and-interaction.md) for SwiftUI specifics. Do not apply a custom gesture progress model to the native Commander split without intentionally taking ownership of its interaction.

## Reduce Motion, lifetime, and nonvisual behavior

For app-owned motion, consult `accessibilityReduceMotion` in SwiftUI or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in AppKit. Select an immediate or reduced-motion visual path while preserving the same semantic endpoint and completion bookkeeping.

The current follower adds no independent spatial animation; it follows whatever geometry the native split produces. A dedicated runtime check with the preference enabled is still needed before claiming accessibility behavior was verified.

Opacity, hit testing, focus, and accessibility exposure are distinct states. A faded view may still intercept clicks or remain focused. When designing custom disappearance, define when each changes and protect cleanup against stale completion. The persistent sidebar button does not fade out or get removed, which avoids that extra state transition.

On detach, invalidate outstanding requests. On reattach, establish which endpoint is actually displayed before resuming. Do not let a delayed callback resurrect an accessory in an old window.
