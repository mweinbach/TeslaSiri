---
name: appkit-animation-control
description: Implement and troubleshoot fine-grained macOS animation with NSAnimationContext, animator proxies, Auto Layout, SwiftUI Animation in AppKit, and Core Animation. Use for retargeting, cancellation, completion races, model versus presentation layers, spring timing, keyframes, pause/resume/scrubbing, Reduce Motion, and animation across NSHostingView or representables.
---

# AppKit animation control

Choose the property owner and animation engine before choosing a curve. Keep final model state correct even if motion is interrupted.

## Routing

- Animating constraints, view properties, or visibility: [AppKit layout recipes](references/layout-and-contexts.md).
- Explicit layers, jumps on interruption, or cleanup: [Core Animation ownership](references/core-animation.md).
- Springs, keyframe sequencing, delay, pause, scrub: [timing and interaction](references/timing-and-interaction.md).
- Shared motion with SwiftUI, representable updates, and verification: [interop and diagnosis](references/interop-and-diagnostics.md).
- API/version evidence: [sources](references/sources.md) and the shared [Xcode research workflow](../nssplitview-control/references/xcode-research.md).

## Workflow

1. Inventory the property to animate, its model owner, whether Auto Layout controls it, and whether the layer is app-owned or AppKit-owned.
2. State the destination, trigger, interruption rule, completion meaning, lifetime, and reduced-motion behavior.
3. Choose the smallest supported route:
   - classic `NSAnimationContext` + animator proxy for AppKit properties;
   - constraint mutation + animated layout for Auto Layout;
   - `NSAnimationContext.animate` for SwiftUI curves on macOS 15+;
   - explicit `CAAnimation` for app-owned layers and time control.
4. Read the routed reference before implementing. Verify the API's actual animation support; an animator proxy does not make every arbitrary setter interpolatable.
5. Keep synchronous UI mutations on MainActor. Treat completion closures according to their imported isolation contract, not just their spelling.
6. Exercise interruption and teardown, then report what was compiled and what motion was observed.

## Rules that prevent subtle failures

- Auto Layout owns constrained geometry. Animate the constraint/layout solution, not the competing `frame` or backing-layer position.
- Lay out the start state before changing constraints. Lay out the smallest common ancestor containing the affected constraints inside the animation context.
- A classic completion can run after cancellation, and can run immediately if no animations were added. It is not an unconditional success callback.
- Protect delayed completion side effects with a request revision. Never remove or hide a view based only on an old request's completion.
- For explicit Core Animation, write the destination to the model layer and animate presentation from the visible current value. Do not use permanent forward fill to hide stale model state.
- Read presentation layers; do not mutate them. They are an approximate snapshot of what is onscreen.
- Use stable animation keys for properties you own. Do not call `removeAllAnimations()` on system-owned layers as a generic cancellation strategy.
- SwiftUI-backed AppKit animations run in-process and are not backed by render-server `CAAnimation`s. `layer.animationKeys()` is not a universal animation inventory.
- Timing constants in these examples are tunable product choices, not platform standards.

## Examples

[AppKitMotionExamples.swift](examples/AppKitMotionExamples.swift) includes a constraint recipe, revision-checked fade, explicit-layer retargeting, dedicated-layer pause/resume, and a transaction-aware representable. Baseline macOS 14; bridge helpers macOS 15.

For split collapse, use `nssplitview-control` to establish geometry first. For SwiftUI view identity and transitions, use `swiftui-animation-control`.
