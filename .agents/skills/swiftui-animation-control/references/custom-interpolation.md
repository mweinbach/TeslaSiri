# Custom interpolation and custom timing

These solve different problems:

- `Animatable`: **what data** SwiftUI interpolates for a view, shape, or effect.
- `CustomAnimation`: **how that data progresses through time**.

Use built-in modifiers and curves when they express the effect. Reach for custom interpolation when a visual parameter is otherwise opaque to SwiftUI; reach for custom timing when the standard curve families cannot express the specified behavior.

## Prefer `@Animatable` synthesis

Apple's existing [custom-animation reference](../../swiftui-specialist/references/animations.md) recommends the macro for straightforward stored-property interpolation. Use `@AnimatableIgnored` for non-interpolated configuration such as a Boolean or style flag.

```swift
import SwiftUI

@Animatable
struct InsetCapsule: Shape {
    var inset: CGFloat
    @AnimatableIgnored var roundedEnds: Bool = true

    func path(in rect: CGRect) -> Path {
        let amount = min(max(inset, 0), min(rect.width, rect.height) / 2)
        let inner = rect.insetBy(dx: amount, dy: amount)
        return Path(roundedRect: inner, cornerRadius: roundedEnds ? inner.height / 2 : 0)
    }
}
```

The ignored flag selects the end treatment immediately; it is not an animated channel. To interpolate that treatment, use a continuous radius instead. A nonnumeric value cannot be interpolated meaningfully merely by including it in a struct. For color/style changes, use the framework's supported style animation or explicitly model a continuous value.

The installed Xcode 27 interface declares the macro as back-deployable to early SwiftUI runtimes, but the compiler/SDK must contain the macro implementation. Do not equate the macro's introduction SDK with a blanket OS 26 deployment minimum. Compile an expansion against the real deployment target to verify it.

## Explicit `animatableData`

Use an explicit implementation when interpolation needs a mapping that is not one-to-one with stored properties, or when using an older compiler without the macro.

| Data | Representation |
| --- | --- |
| One continuous scalar | The scalar itself |
| Multiple continuous values, OS 26+ | `AnimatableValues<A, B, ...>` |
| Multiple values on older deployments | `AnimatablePair`, nested only as needed |

In the example file, `BoundedInsetShape` uses `AnimatableValues<CGFloat, CGFloat>` and a setter that bounds its interpolated values. Its declaration is marked macOS 26+. For the older equivalent, the getter uses `AnimatablePair(inset, radius)` and the setter reads `.first`/`.second` instead of `.value.0`/`.value.1`.

Bounds can protect a path from invalid geometry, but clamping interpolated data can change velocity near the boundary. When the mathematical motion should remain continuous, keep unbounded interpolation data and clamp only the rendered geometry instead. Choose deliberately rather than adding clamps everywhere.

## Mathematical correctness

For `VectorArithmetic`, addition/subtraction/scaling/zero and `magnitudeSquared` must describe a coherent vector space. Do not quietly use arrays of changing length or unrelated IDs as vector components. Fixed-dimension small value types are easier to make correct and efficient.

Angle interpolation deserves an explicit direction policy. A transition from 350° to 10° can travel 340° backward or 20° forward depending on representation. Normalize target deltas to the intended shortest/long path before starting; repeatedly wrapping values during interpolation can introduce discontinuities at the wrap boundary.

For topology-changing paths (different segment counts or shape structures), interpolating a few scalar parameters only works if the path construction remains meaningful at every intermediate value. Use compatible topology, a deliberate morph representation, or a crossfade instead of expecting the system to match arbitrary path elements.

Never perform model updates, task launches, preference writes, or completion callbacks in `animatableData` setters or `Shape.path(in:)`. They are evaluation hooks, not semantic action boundaries.

## CustomAnimation contract, macOS 14/iOS 17+

`CustomAnimation` is `Hashable` and `Sendable`; current requirements are nonisolated. Implement timing as pure value computation and put per-running-animation state in `AnimationContext`, not a shared mutable singleton.

- `animate(value:time:context:)`: produce the current scaled/interpolated vector; return `nil` when the animation has finished so SwiftUI can remove it.
- `velocity(value:time:context:)`: provide a compatible derivative if continuity needs it; the default is nil.
- `shouldMerge(previous:value:time:context:)`: decide whether to merge with previous animation state; the default is false.

Apple documents a subtle point: returning false from `shouldMerge` means both animations can run and the system combines results, **not** “automatically replace the old one.” Returning true transfers prior state/time into the new instance and removes the previous animation. Implement merging only with a coherent state/time model.

The following complete timing example uses smoothstep. It is intentionally illustrative: built-in ease curves are usually sufficient, and this example does not define a custom merge policy.

```swift
import SwiftUI

@available(macOS 14.0, iOS 17.0, *)
struct SmoothStepTiming: CustomAnimation {
    var duration: TimeInterval

    nonisolated func animate<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: inout AnimationContext<V>
    ) -> V? {
        guard duration > 0, time < duration else { return nil }
        let t = max(0, time / duration)
        var result = value
        result.scale(by: t * t * (3 - 2 * t))
        return result
    }

    nonisolated func velocity<V: VectorArithmetic>(
        value: V, time: TimeInterval, context: AnimationContext<V>
    ) -> V? {
        guard duration > 0, time < duration else { return nil }
        let t = max(0, time / duration)
        var result = value
        result.scale(by: 6 * t * (1 - t) / duration)
        return result
    }
}
```

Construct it with `Animation(SmoothStepTiming(duration: 0.3))`. Validate finite duration at the caller if values come from external configuration. If targeting an app with default MainActor isolation, keep this timing type explicitly nonisolated using the supported Swift toolchain's syntax; its protocol callbacks must remain pure and callable off-main.

## Verification for custom math

Unlike a simple opacity tweak, custom vector/timing logic benefits from focused mathematical checks:

- endpoints, zero/negative duration policy, and values near completion;
- finite values and valid path geometry across the full interpolation range;
- derivative behavior where continuity is promised;
- angle wrapping and boundary crossings;
- interruption/merge behavior if implemented;
- no per-frame allocation or expensive model access in a real animation trace.

Sources: [Animatable](https://developer.apple.com/documentation/swiftui/animatable), [AnimatableValues](https://developer.apple.com/documentation/swiftui/animatablevalues), [CustomAnimation](https://developer.apple.com/documentation/swiftui/customanimation), plus Apple's installed `swiftui-specialist` animation reference.
