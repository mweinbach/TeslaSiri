# Timing, springs, phases, pause, and scrubbing

## Start with a motion specification

Write one short specification before adjusting numbers:

```text
property: inspector width, constrained layout
trigger: user toggle
owner: split item/controller
target: collapsed or retained expanded width
curve: quick non-bouncy reveal
interruption: newest target wins; no stale hide/focus completion
reduced motion: immediate geometry
verification: reverse at 25%, 50%, and 75%; resize window mid-flight
```

Geometry, opacity, scale, and content replacement may need different curves. They can share a semantic trigger without sharing one large animation group.

## Curves are not interchangeable duration numbers

### Classic timing functions

`CAMediaTimingFunction` specifies progress over normalized time. Named ease-in/ease-out/ease-in-ease-out curves are suitable for deterministic fixed-duration transitions. Custom cubic control points tune acceleration and deceleration; use them when the visual requirement warrants the added parameters.

`duration` sets the active duration for that classic animation. Delaying or nesting groups does not turn a timing function into a spring with continuous retargeting.

### SwiftUI springs in AppKit, macOS 15+

Import SwiftUI and use:

```swift
// Fragment: card is a view whose geometry is not constrained by Auto Layout.
NSAnimationContext.animate(.spring(duration: 0.32, bounce: 0.08)) {
    card.setFrameSize(destinationSize)
}
```

The modern route uses ordinary mutations inside the `changes` closure. For constraints, mutate the constraint and resolve layout inside that closure. Do not add another classic animator group around the same property.

SwiftUI spring `duration` is perceptual timing, not a guarantee that all residual motion ends at that wall-clock instant. The API documents velocity-preserving retargeting. This engine is in-process and does not produce a backing `CAAnimation` you can scrub through the layer API.

### Physical Core Animation springs

`CASpringAnimation` exposes mass, stiffness, damping, initial velocity, and `settlingDuration`. These have different meanings from SwiftUI's duration/bounce API. Use `settlingDuration` when constructing a spring intended to run until visually settled; keep the model destination explicit.

Do not copy a gesture's pixels-per-second value into a scalar normalized spring velocity without checking the API units and the property displacement. For multidimensional motion, define how velocity components map to the property vector and handle zero-distance targets.

## Keyframes and groups

Use `CAKeyframeAnimation` for an app-owned property's controlled path or intermediate values:

- `values` specifies property values; `keyTimes` specifies normalized times over the animation duration.
- Keep counts and ordering consistent. Include intentional endpoints rather than relying on ambiguous defaults.
- `timingFunctions` controls intervals for modes that honor it.
- With a position path, `calculationMode` controls interpolation; paced modes distribute movement by distance and ignore timing controls documented as inapplicable to that mode.
- `rotationMode` can orient a moving layer along a path. Establish the anchor/pivot before motion.

`CAAnimationGroup` combines child animations under a shared local time. Set a group duration that accommodates child start offsets and active durations. A short group can cut off a longer child. Child begin times are relative to the group, whereas a top-level layer animation uses the layer's local time.

Use different explicit animation keys for independent effects, but one clear owner for each property. Two non-additive animations on the same property do not automatically compose into the intended motion. Additive animations require correctly defined deltas and cleanup; do not casually mix absolute and additive values.

## Delay without a model-state flash

For a top-level delayed layer animation, convert time:

```swift
// Fragment: layer is an app-owned CALayer.
animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
```

If the model already contains the final value, a delayed animation may show that final value until it begins. `.fillMode = .backwards` can hold its `fromValue` during the delay. This legitimate fill-mode use is different from permanently retaining an animation instead of committing model state.

For semantic sequencing, prefer an actual completion/phase system to hardcoded dispatch delays. For deliberate overlapping choreography on app-owned layers, local begin times and keyframe offsets provide precise timing.

## Pause and resume a dedicated layer clock

Layer local time is affected by `speed`, `timeOffset`, and `beginTime`, including ancestor timing. `CACurrentMediaTime()` must be converted with `convertTime` before using it as layer-local time.

The standard pause/resume recipe in the example assumes an app-owned clock with speed 1 before pause:

1. Pause: capture local current time, set speed to 0, put the captured time into `timeOffset`.
2. Resume: retain paused time, restore speed 1, clear offset/begin time, compute local current time minus paused time, and set that as the new begin time.

Changing a parent layer's speed affects its animated descendants. Use a dedicated container layer so pausing a decorative indicator cannot pause unrelated control feedback. If your app already uses non-unit speeds or custom offsets, preserve and restore that full clock configuration rather than copying the unit-speed recipe.

## Scrubbing

For a user-controlled timeline:

1. Put the effect under a dedicated paused layer/time space with an explicitly established origin.
2. Map clamped progress `p` to the animation's local duration: `timeOffset = p * duration` only when the clock origin is defined that way.
3. Keep semantic destination state separate from scrubbed presentation.
4. On release, choose commit, cancel, or animate to the nearest endpoint; reconcile model state and remove temporary animation state.

Do not take an arbitrary layer paused at its absolute local current time and overwrite its offset with `p * duration`; those are different time origins. Do not try to scrub a SwiftUI-backed AppKit animation through Core Animation's clock.

Pointer-driven pane/slider geometry should generally follow input directly. Animate the release or settling behavior instead of easing every incoming pointer sample.

Sources: [NSAnimationContext.animate](https://developer.apple.com/documentation/appkit/nsanimationcontext/animate(_:changes:completion:)), [CASpringAnimation](https://developer.apple.com/documentation/quartzcore/caspringanimation), [CAKeyframeAnimation](https://developer.apple.com/documentation/quartzcore/cakeyframeanimation), [advanced timing and pause/resume](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html).
