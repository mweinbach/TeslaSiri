# SwiftUI interoperability and animation diagnosis

## A representable is an animation boundary

SwiftUI's `withAnimation` configures a transaction. It does not automatically make every arbitrary AppKit mutation in a representable animate correctly. On macOS 15+, use `context.animate(changes:completion:)` to apply the current transaction's animation to AppKit changes.

Both view and view-controller representable contexts provide this method. The installed SDK declares macOS 15.0 availability and back-deployment before macOS 15.4. See [Xcode research](../../nssplitview-control/references/xcode-research.md) for how that distinction was checked.

The bridge should:

- create the AppKit view/controller once;
- compare requested values before starting work;
- establish starting layout if animating geometry;
- call `context.animate` around ordinary property/constraint changes;
- preserve transaction suppression instead of always starting a default animation;
- avoid writing bindings synchronously during `updateNSView`/`updateNSViewController`;
- invalidate deferred completions at teardown.

The SDK implementation executes immediately when no transaction animation is present or animations are disabled. Therefore completion may also be immediate. Set up revision bookkeeping before calling it.

See `NativeEmphasisView` in [the example file](../examples/AppKitMotionExamples.swift). Its alpha is owned by AppKit; the outer SwiftUI transaction provides timing. The parent still owns layout of the representable itself.

## Hosting in the other direction

When AppKit contains an `NSHostingView`/`NSHostingController`, identify whether the effect belongs to:

- the hosting container's AppKit geometry;
- the SwiftUI content's internal state;
- or both, coordinated intentionally with compatible timing.

An AppKit animation group does not grant arbitrary access to SwiftUI internal layers. Pass state into hosted SwiftUI and use its transaction mechanisms for internal content. For shared curves on macOS 15+, use the documented SwiftUI animation route rather than assuming that an identically named Bézier will match a spring.

Apple documents that SwiftUI-backed animations run in-process, rather than as render-server `CAAnimation`s. Do not use missing layer animation keys as proof that nothing is animating; do not use `removeAllAnimations()` as a SwiftUI cancellation API.

## Symptom triage

| Symptom | First suspect | Focused check |
| --- | --- | --- |
| Constraint animation jumps instantly | Missing starting layout or layer backing | Resolve start state; inspect common ancestor and implicit animation route |
| Frame changes then reverts | Auto Layout owns frame | Animate constraint, remove competing frame write |
| Layer snaps back at end | Model never reached target | Commit model destination with actions disabled |
| Reversal jumps | New animation begins from old model target | Read presentation before replacing owned animation |
| Reversal changes speed abruptly | Position continuity without velocity continuity | Use retargetable spring or explicit velocity policy |
| Old fade completion hides newly shown view | Missing request revision check | Validate latest intent before cleanup |
| Completion doesn't wait | No animations added, unsupported property, or immediate path | Verify property/engine; make immediate completion safe |
| AppKit and SwiftUI finish at different times | Different engines/curves or bridge ignores transaction | Use modern transaction bridge and one property owner |
| Layer cancellation has no effect | SwiftUI-backed animation isn't a `CAAnimation` | Cancel/retarget through state and the owning API |
| Shadow clips or jumps | Mask/anchor/path changes | Separate shadow/clipping layers; commit geometry together |
| Motion hitches during resize | Layout, text shaping, rendering, or main-actor work | Profile representative content and invalidations |

## Instrumentation

Log semantic requests and their revisions; use signposts to bound actions and animation completion rather than logging every interpolated value. For layer-specific diagnosis, sample model and presentation properties at a few points and list only animation keys you own.

Use Time Profiler for app work, SwiftUI Instruments for excessive update work when available, and rendering/animation instruments appropriate to the platform for compositing. Distinguish expensive UI recomputation from render-server costs. Offloading unrelated work will not fix a constraint conflict.

Prefer a focused reproduction that removes networking/data decoding from the animation path. Keep a second run with real content to ensure the final design still meets frame budgets.

## Verification matrix

For a new interruptible effect, check:

1. Start, reverse halfway, reverse again; final model and visible state agree.
2. Trigger the same target repeatedly; no endless restarts from unrelated updates.
3. Close/detach the view mid-flight; completion does not resurrect or access stale UI.
4. Enable Reduce Motion and trigger again; the semantic result remains correct.
5. Resize or change content while moving if the real app permits it.
6. Verify focus/hit-testing during a fade or transform, not just opacity.
7. Check a different backing scale if custom layers/text are involved.

Builds and type checks validate API usage. A static preview validates a state. Actual temporal continuity still requires motion observation.
