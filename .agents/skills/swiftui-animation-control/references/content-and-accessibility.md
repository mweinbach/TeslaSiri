# Foreground content, interruption, and accessible motion

Use this reference when an icon, label, or interactive region must change coherently with moving geometry. For Liquid Glass shape identity and fusion, use [fused-glass-morph](../../fused-glass-morph/SKILL.md); this reference owns the SwiftUI foreground and lifecycle decisions.

## Specify separate channels

Write down which values move together before choosing an API. A glass panel expanding into a menu can involve four different channels:

| Channel | Owner and purpose | Decision to make |
| --- | --- | --- |
| Semantic destination | View or model state: expanded, selected action, loading result | What the latest user action means |
| Geometry | Stable view's frame/transform or an explicit animatable value | Whether motion retargets continuously and how layout participates |
| Foreground | Symbol replacement, label opacity, clipping, or independent keyframes | When distinct glyphs have room to remain readable |
| Interaction | Hit testing, enabled state, keyboard focus, accessibility presence | Which action is available during opening, closing, and reversal |

The target Boolean changes synchronously. It does not report whether an expanding frame is currently halfway open. Naming it `progress` or reading it after a delay does not change that contract. Read [transactions and scope](transactions-and-scope.md) for the distinction between model and presentation values.

Do not add staging to an ordinary icon swap unless the surrounding motion creates a concrete legibility or interaction problem. Two separate actions can keep both icons visible inside roomy fused glass. If their glyphs would collide as frames converge, fade the departing glyph before the overlap and reveal it when separation provides room. That timing is a component design choice, not a service supplied by glass fusion.

## Select the foreground mechanism

| Actual change | Appropriate mechanism | Common mistake |
| --- | --- | --- |
| Same `Image` changes its SF Symbol | `.contentTransition(.symbolEffect(.replace))` with animated content change | Using bounce to imply one symbol has become another |
| Existing content changes and a cross-fade is useful | `.contentTransition(.opacity)` where that content supports it | Expecting arbitrary child hierarchies to interpolate as one text run |
| Existing foreground must fade without replacing its content | Animate `.opacity` in a narrow scope | Changing identity merely to hide a persistent guest's icon |
| Child enters or leaves the hierarchy | A view transition plus animated insertion/removal | Applying a transition to a view that never enters or leaves |
| Existing symbol acknowledges an event | `.symbolEffect(..., value:)`, using an event counter or stable event ID | Reassigning the same Boolean and expecting a new event |
| Existing symbol shows an ongoing condition | The `isActive:` symbol-effect overload where the effect supports it | Starting a permanent decorative loop with no lifetime policy |
| Different source/destination content moves between layouts | Geometry correspondence plus a separately designed foreground change | Assuming `matchedGeometryEffect` interpolates the complete rendering |

SF Symbol replacement and discrete symbol effects require macOS 14/iOS 17 or later. Content transitions require macOS 13/iOS 16 or later. Effects apply to symbol images and differ in their supported protocols; compile the exact effect/overload rather than treating every effect as interchangeable. See Apple's [symbol content transition](https://developer.apple.com/documentation/swiftui/contenttransition/symboleffect(_:options:)) and [event-triggered symbol effect](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)).

### Keep the content animation local

This isolated example changes one persistent symbol. The duration illustrates scope; it is not a shared Commander timing rule.

```swift
import SwiftUI

@available(macOS 14.0, *)
struct RunControl: View {
    @State private var isRunning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            isRunning.toggle()
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isRunning)
        }
        .accessibilityLabel(isRunning ? "Stop" : "Run")
    }
}
```

The watched value installs animation in the symbol subtree. It is not a property whitelist: adding other changing modifiers inside that scope could animate them in the same update. Keep streaming text, parent size changes, and unrelated controls outside it. The accessible action label describes current semantics immediately.

`.contentTransition(.identity)` explicitly chooses no content animation; it does not suppress every other animation in the containing control. Likewise, [symbolEffectsRemoved](https://developer.apple.com/documentation/swiftui/view/symboleffectsremoved(_:)) removes inherited symbol effects at a leaf. It is not a cancellation API for an arbitrary geometry spring, keyframe animator, or AppKit effect.

## Choose continuous or staged choreography

Use one of these designs according to how precise the relationship must be.

**Continuous geometry mapping:** if content must appear at a geometric threshold, drive the frame and foreground from the same actual interpolated value. An animatable modifier/shape or keyframe content closure can receive that value and derive frame, clip, and opacity as pure output. For example, opacity can remain zero through a crowded interval and increase after enough separation exists. Base the threshold on the component's layout contract, including larger text and changing content. A `@State` destination of `1` is still not the current interpolated value.

Keep the mapping free of model writes and side effects. Do not assign to `@State`, clear focus, or enable a button from an `animatableData` setter or per-frame callback. If actions must become available at a precise progress boundary, that needs an explicitly owned interaction state/progress architecture; a render callback is not a substitute for it. See [custom interpolation](custom-interpolation.md) and [keyframe interruption](phases-and-keyframes.md#trigger-restart-and-interruption-semantics).

**Semantic staging:** if it is acceptable to reveal content once a geometry action completes, use a guarded completion and a separate small foreground fade. This is simpler than tracking presentation progress, but the completion describes animation lifecycle, not a measured frame or collision test. A geometry action may animate several properties. Choose its scope and [completion criterion](springs-and-interaction.md#completion-criteria-macos-14ios-17) deliberately; `.logicallyComplete` can fire before a spring tail ends, while `.removed` can be deferred by continuing retargeting.

For either design, preserve the geometry participant's identity. If the parent is a persistent glass guest, keeping its icon mounted and animating opacity preserves the guest's geometry path. If the whole feature truly enters/leaves, use the insertion/removal strategy appropriate to that hierarchy.

## Retarget and invalidate follow-up work

Newest intent should own the destination. A staged sequence needs a request revision in addition to the destination state:

```text
receive semantic action
increment revision and capture it
clear any obsolete readiness/follow-up state
commit new destination using the intended geometry transaction
completion:
    confirm captured revision still matches
    confirm current destination and owner still permit the follow-up
    reveal/mark ready in a separate foreground transaction
```

Initialize bookkeeping before the animated mutation: a completion can run immediately if no animation was created. Invalidate old requests when a new action arrives, the owner leaves its active lifetime, or a motion-policy change replaces the staged behavior. Cancellation of a task alone is insufficient if its eventual callback still applies stale state; check cancellation/revision at the commit site.

On closing, remove access to outgoing actions according to the component's semantics immediately; a remaining visual fade need not leave those actions available. On reopening mid-close, re-evaluate both visibility and readiness rather than letting the old close completion hide the reopened content. A Boolean `isAnimating` cleared by every completion cannot establish which request finished.

If a short delay is deliberately part of foreground choreography, keep its owner, cancellation, and revision guard explicit. Do not compute it from a spring's nominal duration or use it as proof that geometry has settled. Avoid queuing every hover event; coalescing to latest intent usually fits reversible hover/disclosure motion.

On first mount or restored state, establish the intended resting pose and readiness directly. Animate subsequent semantic actions where appropriate. Skipping movement must not leave a spinner, hidden label, or disabled action waiting for a completion that the design assumed would happen later. Durable model correctness must remain independent of decorative completion.

## Coordinate drawing with input and focus

Opacity, clipping, and drawing order describe pixels. They do not collectively establish which action owns pointer input, keyboard input, or accessibility. Define each path:

| Path | Required component decision |
| --- | --- |
| Pointer | Choose the live hit region; `allowsHitTesting` controls participation. Decorative overlays should not intercept an underlying control |
| Enabled state | Keep action eligibility tied to semantic availability; decide whether opening needs a readiness gate |
| Keyboard | Release or transfer focus when a control closes; hiding/clipping a mounted native control can leave its first responder active |
| Accessibility | Hide retired or purely decorative duplicates; preserve a single useful action label/value during replacement |

When a menu-like control closes, preserve or restore focus to a meaningful owner according to its actual interaction contract. For SwiftUI focus, use a component-owned `FocusState`; AppKit-hosted controls may also require the owning controller's responder policy. Clearing focus from render interpolation is too late and introduces side effects.

Two surfaces can draw as one glass outline while retaining distinct hit regions. Inventory the overlapping regions and z-order explicitly; the shared outline does not select a winner. A `.contentShape` defines a shape for supported content interactions, not permission for an invisible duplicate action to remain accessible.

Commander has a concrete mounted-native-list focus regression documented in [identity and layout](identity-and-layout.md#commander-history-disclosure). Apply its reusable lesson to similar controls after inspecting their actual focus owner; do not copy that shelf's implementation into every disclosure.

## Honor preferences at the motion owner

[accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion) reports the system preference. Apple asks UI to avoid large motion, especially depth simulation. Choose a suitable alternative per component: immediate frame changes, a small opacity cross-fade, or a static confirmation. Keep the final state and action meaning intact. A short fade is a design option, not a mandatory animation for every reduced-motion update.

[accessibilityPrefersCrossFadeTransitions](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitypreferscrossfadetransitions) is available from macOS 26.4/iOS 26.4. On macOS it returns whether Reduce Motion is enabled; it does not expose a separate macOS cross-fade preference. On iOS it reflects Reduce Motion together with Prefer Cross-Fade Transitions. If supporting older targets, check availability instead of assuming this is an original SwiftUI environment value.

Evaluate the policy where motion starts and where ongoing presentation is owned. Suppressing a broad transaction does not necessarily stop an independent repeating symbol/keyframe effect. For ongoing effects, route to neutral rendered values and stop unnecessary triggers under Reduce Motion; invalidate pending staged callbacks that could restore motion or obsolete content. Verify a preference change while the effect is underway if the component owns such a lifecycle.

Keep material accessibility separate from motion. Reduce Transparency and Increased Contrast concern the glass/readability treatment; they do not automatically solve moving foreground, interaction, or focus. Use the companion [macOS glass motion skill](../../macos-glass-motion/SKILL.md) for those settings and native hosting.

## Observe the sequence that matters

For an implemented morph with coordinated foreground, inspect normal open/close, rapid reversal before and after foreground reveal, dismissal or owner disappearance during motion, and content changes during the same update. Check both pointer and keyboard paths plus accessibility presence while content is hidden. Larger text or a longer label can expose overlap that the default symbol-only pose conceals.

Record the observed behavior and limits: a build confirms API use, a still image shows one pose, and temporal interaction establishes the sequence. Use [Commander verification](../../../../docs/verification.md) when changing runtime behavior. Documentation-only edits need frontmatter/link/whitespace checks and SDK compilation for new API examples; they do not call for an app-wide motion test by themselves.
