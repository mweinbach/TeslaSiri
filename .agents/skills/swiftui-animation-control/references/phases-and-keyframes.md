# Phases, keyframes, and deliberate choreography

## Use the mechanism that matches the specification

| Need | Mechanism |
| --- | --- |
| One target with interruptible motion | State + spring |
| A short sequence of semantic poses | `PhaseAnimator` / `.phaseAnimator` |
| Independent timing for scale, position, rotation, opacity | `KeyframeAnimator` / `.keyframeAnimator` |
| A custom mathematical time function | `CustomAnimation` |
| User-controlled seek/pause of native layer motion | Explicit layer timing; see AppKit skill |

Do not encode an entire animation state machine as a chain of `DispatchQueue.asyncAfter` calls. Timers become stale when triggers repeat, the view disappears, Reduce Motion changes, or animation timing is adjusted.

## Phase animator

A phase is a semantic pose such as idle, lifted, or settled. The animator moves through the provided phases in order and returns to the first phase. The non-triggered form cycles continuously; the triggered form runs in response to a changed equatable trigger.

```swift
// Fragment: confirmationCount changes for each confirmation event.
Image(systemName: "checkmark.circle.fill")
    .phaseAnimator([false, true], trigger: confirmationCount) { content, lifted in
        content
            .scaleEffect(lifted ? 1.1 : 1)
            .offset(y: lifted ? -3 : 0)
    } animation: { lifted in
        lifted ? .snappy(duration: 0.18) : .smooth(duration: 0.24)
    }
```

The animation closure chooses timing for the phase being entered. Keep the first phase a sensible resting pose. A counter or event ID works better than repeatedly assigning `true` when each occurrence should retrigger. Do not generate a fresh random trigger during `body` evaluation.

The fragment omits reduced-motion routing; a production component should either avoid triggering motion or present neutral values under Reduce Motion. See the complete keyframe example for a snapshot-based policy.

Use phases when properties can share each stage's timing. If scale must peak at 120 ms while translation starts later and settles at 400 ms, independent keyframe tracks express that more clearly.

## Keyframe animator

Create a small value type containing the animated channels. Each `KeyframeTrack` addresses one property through a key path. All tracks share the animation's timeline, but their segments can have different durations.

| Keyframe | Behavior |
| --- | --- |
| `LinearKeyframe` | Linear interpolation toward a value |
| `CubicKeyframe` | Smooth curve interpolation with velocity-related control |
| `SpringKeyframe` | Spring segment, optionally with explicit duration/velocity |
| `MoveKeyframe` | Immediate change, useful for an intentional step |

For a hold, give an interval the same target as its current value. A `MoveKeyframe` is a step, not a time-consuming hold. Account for each track's total duration; shorter tracks retain their endpoint while longer tracks continue.

See `KeyframeConfirmation` in [the examples](../examples/SwiftUIMotionExamples.swift): scale and vertical translation have independent tracks, with explicit return-to-rest endpoints.

## Trigger, restart, and interruption semantics

Apple documents for the trigger-based keyframe API:

- Initially, `keyframes` receives `initialValue`.
- At completion, the animator stays at its final value; that becomes the starting value for the next run.
- If the trigger changes mid-animation, `keyframes` receives the current interpolated value and defines a replacement animation.
- Previous velocity is preserved for cubic/spring continuity when those segments do not override initial velocity.

Therefore do not assume every event starts from the original initial value. Return to a neutral pose explicitly if each event should end there. If recomputing a path based on current values, use the provided value rather than separately reading a target state that is already at the endpoint.

A fixed-duration segment can begin from a different intermediate point on retrigger. Inspect rapid repeated input; it may produce a different peak or pacing than isolated runs. Define whether to restart, merge, coalesce, or queue events based on the effect's meaning. An event queue is an application policy, not an automatic property of keyframes.

## Keep frame callbacks pure

The `content` closure runs every animation frame and is `@Sendable` in the current SDK. Capture immutable, small, Sendable snapshots such as a local Reduce Motion Boolean. Avoid capturing a MainActor view model, dispatching tasks, sorting arrays, loading images, or formatting large text there.

The keyframe values should be cheap value data. Apply transforms/opacity to existing content rather than rebuilding an expensive hierarchy per frame. State changes belong at the event boundary, not inside the interpolated content closure.

For precise action sequencing that has semantic consequences, use actual completion or explicit state-machine transitions outside per-frame callbacks. Visual phase changes should not secretly send network requests or commit document edits.

## Accessibility and repeat policy

- An important confirmation should still have a visible/static result and accessible label without motion.
- Under Reduce Motion, present neutral scale/offset and avoid starting unnecessary loops.
- If Reduce Motion changes mid-flight, neutral presentation should take effect coherently rather than leaving the icon at a lifted pose.
- Repeated decorative effects should have a clear visibility/lifetime policy; do not let a hidden screen continuously animate expensive content.

Sources: [controlling timing and movement](https://developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations), [PhaseAnimator](https://developer.apple.com/documentation/swiftui/phaseanimator), [triggered keyframes](https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)).
