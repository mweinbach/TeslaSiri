# Springs, interruption, gestures, and completion

## Choose a spring by behavior

| API family | Control | Useful distinction |
| --- | --- | --- |
| `.smooth`, `.snappy`, `.bouncy` | Preset character plus duration/extra bounce | Good starting points for product motion |
| `.spring(duration:bounce:blendDuration:)` | Perceptual pace and overshoot | Duration is not an exact full-settling deadline |
| `.spring(response:dampingFraction:blendDuration:)` | Response and damping model | Different parameterization; do not copy duration/bounce values blindly |
| `.interpolatingSpring(...)` | Interpolating spring and optional initial velocity | Understand overlap/additive behavior for the selected overload |
| `.timingCurve` / ease curves | Fixed-duration progress curve | Better when deterministic non-spring timing is the goal |

For `spring(duration:bounce:)`, Apple documents bounce 0 as critically damped; positive bounce increases oscillation toward 1, and negative values represent overdamping down to -1. Do not expose the full mathematical range as an unbounded product tuning control. A sidebar generally benefits from less overshoot than a celebratory icon.

Use a tiny, named motion palette if several components share behavior. Store `Animation` values or functions returning them, and apply Reduce Motion at the usage site. Avoid a global “all UI animation duration” constant that forces unrelated effects into the same pacing.

## Retarget the existing identity

Persistent spring animations can replace successors on the same property while preserving velocity according to the spring API contract. Keep the view identity and animatable property stable, then change the destination.

Replacing the whole view, changing the animatable representation, or starting a separate layer animation can lose that continuity. “Same curve name” does not prove the same animation history.

For rapid toggles, newest intent should win. Do not disable input for the nominal duration unless blocking interaction is a deliberate product requirement. Making the effect robust to reversal usually produces better control.

## Completion criteria, macOS 14/iOS 17+

`withAnimation(_:completionCriteria:_:completion:)` and `Transaction.addAnimationCompletion` avoid guessed timers.

| Criterion | Meaning under interruption |
| --- | --- |
| `.logicallyComplete` | The original change logically completes, possibly while its spring tail remains; later animations do not extend that callback's criterion |
| `.removed` | The animation is fully finished/removed; subsequent animations on affected properties can defer completion until all are complete |

Apple documents that transaction completions fire exactly once; when no animations are created, they can fire immediately after the mutation body. Never depend on “completion will run later” to initialize bookkeeping.

`.removed` can be delayed by ongoing retargeting and is not suitable for an action that must occur at a bounded time regardless of new input. `.logicallyComplete` can fire while another newer motion is still underway. Neither means “the user still wants the state this closure captured.”

Use the revision pattern from `CompletionAwarePanel` in the example:

```text
revision += 1
capture revision
withAnimation(..., completionCriteria: chosen) { update destination }
completion: guard captured revision == current revision, then apply follow-up
```

Increment/invalidate the revision when the effect's owning view leaves its intended lifetime. For essential model operations, do not make business correctness depend on decorative animation completion.

`Animation.logicallyComplete(after:)` adjusts logical completion reporting. It does not force a short animation to keep running after it actually ends.

## Gesture handoff

Separate three quantities:

1. Persistent resting target.
2. Current gesture translation/progress.
3. Rendered intermediate animation value.

While dragging, update translation directly, usually with no interpolation. A transaction in `Gesture.updating` can set `animation = nil` for tracking. On release, choose a destination using position and, where appropriate, projected/velocity information, then spring to it.

`predictedEndTranslation` is a predicted displacement, not a velocity in points per second. Do not pass it unchanged into a spring's initial-velocity argument. Verify units and normalize against travel distance for the selected API.

### Gesture-state reset is a separate update

`@GestureState` resets when a gesture ends or cancels. Its reset transaction can differ from the persistent-state mutation in `onEnded`. If the resting state animates while translation resets immediately, the composed view can jump.

Use an intentional `resetTransaction`, or a design that reconciles persistent offset and temporary translation coherently. Verify both normal release and cancellation; `onEnded` alone is not the complete cancellation policy.

### Re-grabbing an in-flight spring

The persistent state contains the target, not the visible intermediate position. Starting the next drag from that target can jump under the pointer. If exact re-grab continuity is required, choose an interaction architecture that tracks the continuous presentation/progress through supported APIs, or use an explicitly owned animator with a presentation/scrub surface.

Do not write model state from an `animatableData` setter every frame to invent a presentation binding. That creates update loops, changes animation semantics, and can violate isolation.

## Repeated animation and lifetime

Use phase/keyframe animators with explicit trigger/repeating semantics for staged effects. `repeatForever` is appropriate for an intentional persistent visual effect, but not as an unowned fire-and-forget task.

On visibility/lifetime changes, define whether the effect pauses, stops, or restarts. For model-driven repeat animations, ensure the relevant state/transaction actually removes or replaces the effect; assigning the same target again may not trigger any update. Do not rebuild the whole screen with a new ID merely to stop one decorative pulse.

Respect Reduce Motion in both initial triggering and any ongoing visual presentation. Keep progress/status meaning available even when movement is removed.

Sources: [spring](https://developer.apple.com/documentation/swiftui/animation/spring(duration:bounce:blendduration:)), [completion criteria](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria), [transaction completion](https://developer.apple.com/documentation/swiftui/transaction/addanimationcompletion(criteria:_:)), [GestureState](https://developer.apple.com/documentation/swiftui/gesturestate).
