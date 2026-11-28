---
name: swiftui-animation-control
description: Design and debug precise SwiftUI motion using transactions, scoped animation, springs, completion criteria, content transitions, matched geometry, gestures, phases, keyframes, and custom interpolation. Use for unintended sibling animations, foreground choreography, snapping, interrupted transitions, Reduce Motion, repeat lifecycles, and coordinated AppKit animation.
---

# SwiftUI animation control

SwiftUI state describes the destination. A transaction specifies how eligible visual values reach it. Identity determines whether SwiftUI updates an existing view or transitions between different views.

## Read by task

| Task | Reference |
| --- | --- |
| Animate only the intended property; suppress unrelated motion | [Transactions and scope](references/transactions-and-scope.md) |
| Insert/remove/reorder, morph geometry, avoid layout jumps | [Identity and layout](references/identity-and-layout.md) |
| Retarget springs, handle gestures and completions | [Springs and interaction](references/springs-and-interaction.md) |
| Stage icons/labels, coordinate interaction and focus, honor motion preferences | [Content and accessibility](references/content-and-accessibility.md) |
| Multi-stage motion, independent tracks, repeated feedback | [Phases and keyframes](references/phases-and-keyframes.md) |
| Custom shape/view interpolation or timing engine | [Custom interpolation](references/custom-interpolation.md) |
| Diagnose motion or verify availability | [Diagnosis and sources](references/diagnostics-and-sources.md) |

## Workflow

1. Record the state owner, stable identity, animated properties, trigger, intended curve, interruption behavior, and Reduce Motion alternative.
2. Determine whether this is value interpolation, insertion/removal, content replacement, layout redistribution, or a staged effect.
3. Use the narrowest suitable animation scope. Read the relevant reference before adding a root-level animation modifier.
4. If defining `Animatable` types, consult Apple's existing `swiftui-specialist` animation reference as well. Prefer `@Animatable` when the SDK supports synthesis; use explicit data only for custom mapping or toolchain compatibility.
5. Verify the SDK and deployment target per API. Modern spring/phase/keyframe/completion APIs are macOS 14/iOS 17-era; `AnimatableValues` requires OS 26. Macro availability is also a compiler/SDK question.
6. Check rapid reversal, unrelated state updates, identity/lifetime changes, and reduced motion before declaring the effect correct.

## Core rules

- `withAnimation` changes transaction metadata around synchronous state changes. It does not interpolate the stored model value over time or span an `await` automatically.
- Make an `@Observable` model's related changes inside one `withAnimation`. With another change made just before it, SwiftUI has rendered synchronously inside the animated property's change to flush the earlier one, read the old value, and missed the new one, so the view stayed in its old pose. On macOS 27.2 this hit about a third of runs; see [the effort card](../../../docs/effort-slider.md#one-raised-glass-layer).
- `.animation(_:value:)` is a change trigger and subtree scope, not a dependency filter that excludes every other property changing in that update.
- Use `.animation(_:body:)` for tightly scoped modifier animation. Modifier order and layout propagation still matter.
- A transition needs insertion/removal and an animated transaction. A numeric content transition needs a change to content; neither creates its own trigger.
- Geometry, foreground replacement, and interaction readiness can have different owners and timing. Do not use the final state target as a measurement of the current visible frame; see [content and accessibility](references/content-and-accessibility.md).
- Maintain stable semantic identity. `.id(UUID())` and identity resets are not animation fixes.
- A spring's perceptual duration is not its guaranteed final settling time. Use real completion criteria for sequencing.
- Completion is not proof that the captured request is still current. Recheck intent/revision.
- Gesture motion should track input directly; animate the handoff to a resting state. Treat gesture-state reset as its own transaction.
- Keep interpolation, path generation, custom timing, and keyframe content cheap and free of model side effects. Respect `nonisolated`/`@Sendable` callback signatures.
- Do not infer a SwiftUI presentation value from the final `@State` target or try to stop SwiftUI animation by removing backing-layer animations.
- The shared `withAnimation`, `.highFrameRateAnimation(_:value:)` and `.highFrameRateMotion()` helpers add an invisible frame animation alongside custom morphs to encourage SwiftUI's high-refresh scheduling. They do not guarantee 120 Hz. Verify actual pacing on a ProMotion device, separately from simulator lifecycle tests.
- Never import private `Transaction` symbols (`animationFrameInterval` / `animationReasons`), which trigger App Store Connect `ITMS-90338`, or use reflection to mutate SwiftUI's hosting display link. COMMANDER2-7V crashed in that reflected link's frame-rate setter on iOS 27.2. The stack establishes the unsafe access path, not the exact ownership failure. Use `link.requestHighFrameRate()` only on display links the app created itself.

## Implementation assets

[SwiftUIMotionExamples.swift](examples/SwiftUIMotionExamples.swift) contains a scoped disclosure, revision-aware completion, independent keyframe tracks, a synthesized shape, and an explicit custom interpolation mapping.

For native view/controller changes, read `appkit-animation-control` and use the transaction bridge where supported. For split panes, resolve sizing with `nssplitview-control` first.
