---
name: liquid-glass-animations
description: >-
  Guides high-efficiency 120Hz Liquid Glass animations, shape morphing, container batching, spring choreography, and haptic polish on iOS 26 and iOS 27.
  Use whenever animating Liquid Glass elements, deciding whether to morph vs. materialize vs. cross-fade, optimizing GPU/refraction performance, diagnosing frame drops with Instruments, or choosing Core Animation / UIKit / Metal animation escape hatches.
---

# Liquid Glass Animations & Morphing Craft (120Hz GPU Efficiency)

Great motion is **UX clarity, not decoration**. When a user taps a control and watches a floating pill morph smoothly into its sub-actions—or feels a crisp interruptible spring follow their thumb at 120Hz—the interface communicates **spatial cause-and-effect, physical continuity, and instant responsiveness** without a single word of explanation. Conversely, sloppy morphs, locked timers, or dropped frames shatter perceived speed and trust.

Technically, Liquid Glass is an **optical shader material**, not a cheap flat fill. Every unbatched glass view forces multi-pass GPU backdrop sampling, distortion lensing, noise blending, and specular border shading. Shape animations to be **physically inevitable, interruptible, and 100% idle at rest**.

## Step 1: Decide *Whether* to Morph (The Restraint Rule)

Morphing is powerful only when two UI states share genuine **spatial or functional identity**. Over-morphing turns an app into a lava lamp. Consult [references/morphing-decision-tree.md](./references/morphing-decision-tree.md) before adding a `@Namespace`:

| Interaction | Right Transition | Why |
| :--- | :--- | :--- |
| Button expands into related sub-actions (e.g., `+` → `Note` + `Photo`) | **Morph (`.matchedGeometry`)** inside `GlassEffectContainer` | Clear cause-and-effect lineage; glass splits/merges organically |
| Mode switch on the same control (e.g., compact pill ↔ expanded pill, `Play` ↔ `Pause` tray) | **Morph (`glassEffectID` + shared `@Namespace`)** | Keeps the user's eye anchored on one continuous physical object |
| Split controls sharing one logical group (e.g., multi-part dock or segmented controls) | **Union (`glassEffectUnion(id:namespace:)`)** | Unifies distant views into one cohesive refractive pool |
| Unrelated transient HUD, toast, or contextual tool appearing mid-screen | **Materialize (`.glassEffectTransition(.materialize)`)** + `.opacity.combined(with: .scale(scale: 0.95))` | Avoids awkward stretched blobs pulling across the viewport |
| Toggling active/inactive glass styling on an existing button | **In-place `.glassEffect(isActive ? .regular : .identity)`** | Zero structural view-tree churn; instant GPU-friendly transition |
| Scrolling list cards, long-form content, or distant navigation destinations | **No glass morphing** (standard SwiftUI springs / `navigationTransition(.zoom)`) | Glass belongs strictly to chrome; content moves cleanly underneath |

## Step 2: Enforce the 7 Laws of 120Hz Liquid Glass Performance

Read [references/gpu-performance-120hz.md](./references/gpu-performance-120hz.md) for deep GPU mechanics and Instruments profiling:

1. **Always Batch Nearby Glass Inside One Scoped `GlassEffectContainer`:** Unbatched sibling `.glassEffect()` views execute separate GPU sampling passes. Wrap adjacent chrome in a *local* `GlassEffectContainer(spacing:)` — never wrap the entire screen in one giant container (which bloats path-blending cost).
2. **Never Conditionally Add/Remove `.glassEffect()` Modifiers:** Use `.glassEffect(isActive ? .regular : .identity)` instead of `if isActive { view.glassEffect() } else { view }` so SwiftUI never tears down and rebuilds view identity.
3. **Keep Glass at Rest When Idle:** Never attach `.repeatForever()` animations (pulsing scales, continuous rotations, animated gradients) directly to a `.glassEffect()` surface—continuous backdrop resampling causes thermal throttling and drops ProMotion below 120Hz.
4. **Never Animate `.rotationEffect()` Directly on a Glass Layer:** Rotating a view carrying `.glassEffect()` breaks bounding-box math and warps capsules into distorted ovals mid-flight. Rotate only the **inner glyph** (`Image`) or apply transforms to a clean outer wrapper.
5. **Drive Morphs with Explicit `withAnimation` Blocks:** Always wrap the state toggle in `withAnimation(reduceMotion ? nil : .snappy)` (or `.smooth`). Missing animation contexts bypass morphing physics and snap abruptly.
6. **Isolate `@Observable` State Updates:** Never let a 60Hz timer or scroll offset re-evaluate the `body` of a parent holding `GlassEffectContainer`. Push high-frequency reads into tiny leaf subviews (or `PhaseAnimator` / `KeyframeAnimator`) so glass containers only re-render when their own state changes.
7. **Always Gate Morphing on `accessibilityReduceMotion`:** Fluid morphing and lensing distortion can trigger motion sickness; read `@Environment(\.accessibilityReduceMotion)` and substitute crisp cross-fades or `nil` animation when enabled.

## Step 3: Tune Springs, Haptics & Escape Hatches

- **Physical Springs & Haptics:** Pair `.snappy` / `.smooth` springs with subtle `.sensoryFeedback(.impact(flexibility: .soft), trigger:)` so glass feels tactile like real optics. See [references/springs-haptics-motion.md](./references/springs-haptics-motion.md).
- **When to Drop Below SwiftUI for Motion:** If Instruments (**SwiftUI** + **Core Animation Hitch Rate** + **Flash Updated Regions**) reveals hitches during gesture-driven scrubbers, massive interactive grids, or custom physics, bridge `UIViewPropertyAnimator` / `CADisplayLink` / `UIGlassContainerEffect` or a `Canvas` / Metal shader island so frame pacing stays locked at 120Hz.

## Code Examples

- [examples/MorphingActionCluster.swift](./examples/MorphingActionCluster.swift) — Production `GlassEffectContainer` + `glassEffectID` + `glassEffectUnion` + `.matchedGeometry` / `.materialize` + `accessibilityReduceMotion` + `.sensoryFeedback`
- [examples/EfficientGlassStateToggle.swift](./examples/EfficientGlassStateToggle.swift) — Zero-churn `.identity` toggling, safe inner-icon rotation (avoiding glass bounds warp), and `PhaseAnimator` event-driven feedback without infinite GPU loops
