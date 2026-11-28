# Choose an animation engine deliberately

## Routing table

| Requirement | Mechanism | Key condition |
| --- | --- | --- |
| Move an accessory with an already-moving native sidebar | Geometry follower | Read current geometry; no second interpolator |
| Animate SwiftUI-owned visual values | Scoped transaction / `withAnimation` | Stable identity and animatable properties |
| Insert/remove SwiftUI content | Transition with animated transaction | Insertion/removal is actually occurring |
| Change text/symbol content | Content transition / supported symbol effect | This is content replacement, not view travel |
| Animate AppKit properties | `NSAnimationContext` and supported animator route | The app owns the property |
| Animate an Auto Layout solution | Constraint changes and animated layout | Resolve starting layout; one geometry owner |
| Bridge a SwiftUI transaction into AppKit | Representable `context.animate` | Check supported OS/transaction behavior |
| Drive an app-owned layer directly | Explicit Core Animation | Commit model destination; preserve presentation at interruption |
| Define custom shape interpolation | `Animatable` / `@Animatable` | Pure, coherent interpolated data |
| Define a custom time function | `CustomAnimation` | Standard curves are insufficient; explicit merge policy |
| Stage multiple effects | Phase/keyframe animator or completion-driven sequence | State lifetime and interruption are specified |

Do not choose an engine because an API's name includes “animation.” First identify whether the desired effect is a value change, reflow, clipping/reveal, transform, insertion, material response, or choreography.

## SwiftUI transactions and identity

Read [transactions and scope](../../swiftui-animation-control/references/transactions-and-scope.md) and [identity and layout](../../swiftui-animation-control/references/identity-and-layout.md).

- `withAnimation` supplies transaction metadata to synchronous changes; it does not turn stored `@State` into a stream of intermediate values.
- An `await` is a boundary. Updates after it need their own intended transaction scope.
- `.animation(_:value:)` is a trigger/scope, not a guarantee that only the named dependency animates. Other changes in the same subtree/update can participate.
- Scope modifier animation narrowly when unrelated content, transcript text, badges, or tool output must remain stable.
- `if` branches, `.id`, changing ancestor identity, and `ForEach` IDs can replace subtrees. Use semantic identity; do not generate a new UUID to “refresh” an animation.
- Matched geometry can coordinate appropriate layouts, but is not proof that one native control survives an AppKit toolbar relocation.
- State retention and geometry continuity are separate things to inspect.

For a project example that separates native geometry following from a hosted SwiftUI morph, read [Commander workspace chrome](../../../../docs/workspace-chrome.md). Its production source owns the current placement and hosting details.

## AppKit properties and constraints

Read [layout and contexts](../../appkit-animation-control/references/layout-and-contexts.md).

For constraints, lay out the start state, mutate the constraint, and animate layout at the smallest ancestor that owns the affected geometry. Do not also write the constrained view's frame. A proxy does not make every arbitrary setter animatable; verify support for the actual property.

A manually laid-out, app-owned follower can apply measured geometry with direct frame writes without asking AppKit to interpolate a second path. See [the Commander example](../../../../docs/workspace-chrome.md) for that ownership boundary.

`NSAnimationContext.animate` and representable `context.animate` provide modern SwiftUI-animation integration on supported macOS versions. Use the [interop reference](../../appkit-animation-control/references/interop-and-diagnostics.md) to verify the exact overload, availability, transaction suppression, and completion behavior. A SwiftUI animation around a representable does not automatically make arbitrary native frame writes follow it.

## Core Animation model versus presentation

Read [Core Animation ownership](../../appkit-animation-control/references/core-animation.md).

For a layer the app truly owns:

1. Capture presentation geometry before replacing the current owned animation.
2. Set the model layer to its final destination with implicit actions disabled when appropriate.
3. Animate from the captured visible value to the destination under a stable app-owned key.
4. On immediate/cancel paths, remove only the animation that this owner manages.
5. Protect semantic cleanup with revision checks.

Do not use permanent forward fill to hide a stale model value. Do not call `removeAllAnimations()` on SwiftUI/AppKit/glass backing layers as a generic stop mechanism. Reading a presentation layer for diagnosis is different from taking ownership of it.

SwiftUI-backed animations can run in-process rather than as render-server `CAAnimation`s. Empty `animationKeys()` does not establish that nothing is moving, and a presentation-layer sample is not a universal SwiftUI progress API.

## Custom interpolation and timing

Read [custom interpolation](../../swiftui-animation-control/references/custom-interpolation.md), and load Apple's `swiftui-specialist` animation reference before generating custom SwiftUI animation code.

Separate these responsibilities:

- **Interpolation data:** which continuous scalar/vector values define the view or shape.
- **Timing:** how those values evolve over time.
- **State machine:** what the user wants and which completion is still relevant.
- **Rendering:** how the current values produce pixels.

Use built-in animatable modifiers first. Prefer `@Animatable` synthesis where supported and appropriate. `AnimatableValues` is an OS 26-era option for multiple values; compiler macro availability and runtime availability are different checks. Explicit `animatableData` is useful for a real mapping requirement, not merely as boilerplate.

Keep interpolation and `CustomAnimation` callbacks pure and compatible with their nonisolated/Sendable requirements. Use `AnimationContext` for per-running-animation state instead of a main-actor singleton. Returning false from `shouldMerge` is not simply “replace the old animation”; follow the documented combination/merging behavior.

Custom math needs meaningful validation: finite parameters, endpoint behavior, derivatives where velocity continuity is promised, angle wrapping, path topology, interruption, and allocation cost. Keep clamps deliberate: a mathematically safe clamp can still introduce a velocity discontinuity.

## Phases, keyframes, and independent visual state

Read [phases and keyframes](../../swiftui-animation-control/references/phases-and-keyframes.md).

Use phases for discrete stages and keyframes for explicitly coordinated tracks. A keyframe trigger is not a reason to reset semantic view identity. Repeated/looping effects should be tied to the actual lifecycle and should stop when their owning view or task ends.

For a glass accessory with custom feedback, document each track separately:

```text
translation:  native reveal follower
material:     persistent GlassEffectContainer + glassEffectID + converging Capsule frames
press:        regular interactive glass
symbol:       native content / supported symbol effect
status:       semantic state, outside broad animation scope
```

Do not animate a live geometry stream again through a keyframe or spring. For multi-stage stateful work, use [revision-safe state](state-and-interruption.md) to prevent an old stage from completing after the intent changes.

## Performance

Stable identity avoids unnecessary reconstruction, but does not guarantee low rendering cost. Profile the actual content and material:

- avoid per-frame published state that invalidates the entire workspace;
- keep follower math small and allocation-free;
- when a follower must poll, sample from the window's `displayLink(target:selector:)` (macOS 14+) rather than a fixed-rate `Timer`, so samples land once per frame of the window's current display; bound it, invalidate it on detach, and use a weak target because the link retains its target;
- coalesce redundant geometry invalidations;
- batch similar glass when appropriate;
- avoid logging every frame in production;
- distinguish main-actor layout/text work from material/compositor cost;
- use Instruments when samples indicate hitches rather than smoothing over them with another animation.

The observed visual success of a test window does not establish a universal frame-rate budget. Verify with realistic transcripts and active UI updates when changing performance-sensitive content.
