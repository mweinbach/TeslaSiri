# AppKit properties, constraints, and completion

## Engine selection

| Requirement | Route | Why |
| --- | --- | --- |
| Fade an `NSView` | `view.animator().alphaValue` in a group | Uses AppKit's animatable-property support |
| Resize constrained content | Change constraint, animate layout | Preserves layout ownership |
| Move unconstrained view | Supported frame property through animator | No competing solver |
| Collapse a managed split item | Item collapse APIs | Controller owns pane geometry |
| Retarget using a SwiftUI spring | `NSAnimationContext.animate` (macOS 15+) | Documented velocity-preserving retargeting |
| Pause/scrub a custom indicator | App-owned `CALayer` + `CAAnimation` | Explicit time and animation-key control |

`NSAnimationContext` is a nestable per-thread context, similar in concept to `CATransaction`. It is not an animation handle with a general `cancel()` method. An inner group inherits properties initially, then can override duration or timing for changes it starts.

## Classic animator proxy

```swift
// Fragment: view is an existing NSView on MainActor.
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.18
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    view.animator().alphaValue = 0.4
}
```

Import `AppKit` and `QuartzCore` for this route. The proxy invokes supported animatable setters; it does not guarantee interpolation for any selector you invent. For custom properties, consult `NSAnimatablePropertyContainer`, `animation(forKey:)`, and `defaultAnimation(forKey:)` rather than assuming a plain stored Swift property will work.

Do not keep a proxy as long-lived state. Request it at the mutation site. Avoid simultaneously animating `view.alphaValue` through AppKit and `view.layer.opacity` through Core Animation.

## Auto Layout: establish -> mutate -> solve

For a width, height, or spacing constraint:

1. Ensure the relevant content is layer-backed before starting classic implicit layout animation.
2. Call `layoutSubtreeIfNeeded()` on the appropriate container to establish the starting geometry.
3. Enter `runAnimationGroup` and set duration/timing.
4. Enable `allowsImplicitAnimation`.
5. Change the constraint's constant.
6. Call `layoutSubtreeIfNeeded()` on the same affected ancestor inside the group.

```swift
// Fragment: container owns the relevant layout; width is active.
container.layoutSubtreeIfNeeded()
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.24
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    context.allowsImplicitAnimation = true
    width.constant = destinationWidth
    container.layoutSubtreeIfNeeded()
}
```

The installed AppKit header says `allowsImplicitAnimation` defaults to false and is applicable to layer-backed animation. Using an animator proxy enables it for related changes. Explicitly enabling it in a constraint/layout group makes the intended route clear.

Set `wantsLayer` during view setup, not by toggling layer backing at every animation. Apply layout at the smallest common ancestor that actually contains the affected constraints; laying out only the resized child may not solve a constraint owned by its parent. Laying out the entire window unnecessarily can pull unrelated changes into the group.

Do not animate a constrained `frame` in parallel. If the constraint changes but the starting layout was never resolved, AppKit may only see the final geometry and the view appears to jump. If a descendant's content changes its minimum mid-flight, the solver may alter the trajectory—fix or deliberately sequence that content change.

## Hiding versus fading versus removing

These are separate operations:

- `alphaValue = 0`: visual fade; the view still exists and its input/accessibility behavior needs deliberate handling.
- `isHidden = true`: visibility state, not a continuous opacity value.
- removal from the hierarchy: changes layout/lifetime and may affect focus.

To reveal, unhide before fading in. To hide after a fade, set `isHidden` only if that hide request is still current when completion runs. Do not remove a view from the hierarchy at the beginning of a fade-out and expect the removed view to keep rendering normally.

For text fields and buttons, decide when input should disable and where the first responder should move. An opacity change is not a substitute for an interaction policy. A snapshot can be used for visual-only transitions, but the live accessibility and input tree still needs to reflect the intended state.

## Completion semantics and concurrency

Apple documents that a context's completion handler runs on the main thread after affected animations **complete or are cancelled**. If no animations were added, or the completion handler is replaced, it can run immediately. Set required request state before starting the group, not after.

The current SDK imports the group completion as `@Sendable`. To access MainActor state inside it, use an explicit isolation bridge justified by the documented main-thread guarantee, such as `MainActor.assumeIsolated { ... }`. Alternatively hop with `Task { @MainActor in ... }` and accept that the extra scheduling requires another stale-request check. Do not use the synchronous assertion pattern for unrelated callbacks without such a guarantee.

Use a revision:

```text
increment revision before request
capture revision in completion
on completion: if captured != current, return
then perform current request's UI cleanup
```

This protects semantic cleanup even when a previous animation is replaced. It does not itself cancel rendering or guarantee velocity continuity. See the standalone `FadeCoordinator` example.

Avoid `asyncAfter(duration)` for completion. Delay constants fail when animations are disabled, retargeted, cancelled, slowed, or include spring tails.

## Reduced motion

Read `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` at action time. For a persistent custom motion component, observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` through the workspace notification center and update its policy when settings change.

An immediate state transition is a valid reduced-motion implementation. If using a short dissolve, specify it explicitly as the product's reduced-motion alternative. A zero-duration group is not automatically a safe way to cancel an existing animation owned by another route; apply the owner's explicit snap/cancel policy and keep final state coherent.

Sources: [NSAnimationContext](https://developer.apple.com/documentation/appkit/nsanimationcontext), [runAnimationGroup](https://developer.apple.com/documentation/appkit/nsanimationcontext/runanimationgroup(_:completionhandler:)), [completionHandler](https://developer.apple.com/documentation/appkit/nsanimationcontext/completionhandler), [allowsImplicitAnimation](https://developer.apple.com/documentation/appkit/nsanimationcontext/allowsimplicitanimation).
