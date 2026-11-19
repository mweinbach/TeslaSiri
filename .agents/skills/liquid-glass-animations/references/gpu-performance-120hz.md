# GPU Performance & 120Hz ProMotion Optimization for Liquid Glass

On 120Hz ProMotion displays, you have **8.33 ms total per frame** (CPU layout + SwiftUI diff + Core Animation commit + GPU multi-pass fragment shaders). Liquid Glass adds real GPU weight—knowing where that budget goes prevents frame drops and thermal throttling.

---

## 1. Why Naive Liquid Glass Tanks FPS

Every isolated `.glassEffect()` view executes a multi-stage GPU pipeline:
1. Captures/samples the underlying framebuffer pixels.
2. Runs refractive lensing distortion + adaptive luminosity filtering.
3. Synthesizes specular edge highlights and adaptive perimeter borders.
4. Blends into the final compositor layer.

**The 4 Biggest Frame-Killers:**
1. **Unbatched Glass Siblings:** 8 floating buttons without `GlassEffectContainer` = 8 independent backdrop sampling passes.
2. **Glass-on-Glass Overdraw:** Placing a glass pill on top of a glass sheet on top of a glass card multiplies pixel overdraw exponentially—and looks visually muddy anyway.
3. **Conditional Modifier Churn:** Writing `if selected { view.glassEffect() } else { view }` destroys and recreates the underlying render node every toggle, causing hitch spikes.
4. **Upstream State Leakage (`@Observable` Invalidations):** Reading a high-frequency timer (`Date.now`) or scroll offset inside the same `View` struct that owns a `GlassEffectContainer` forces SwiftUI to diff and re-submit the entire glass cluster 60–120 times per second.

---

## 2. Concrete Optimization Techniques

### A. Use `.identity` Instead of Conditional Modifiers
```swift
// ✅ Zero structural tree churn
Button("Pin", systemImage: "pin") { isPinned.toggle() }
    .glassEffect(isPinned ? .regular.tint(.orange).interactive() : .identity, in: .capsule)

// ❌ Forces structural view rebuild on every tap
if isPinned {
    Button("Pin", systemImage: "pin") { isPinned.toggle() }
        .glassEffect(.regular.tint(.orange).interactive(), in: .capsule)
} else {
    Button("Pin", systemImage: "pin") { isPinned.toggle() }
}
```

### B. Keep Glass "At Rest" (Zero Infinite Loops)
- Never apply `.repeatForever()` scaling, pulsing opacity, or spinning `.rotationEffect()` to a `.glassEffect()` surface.
- If you need an event-driven multi-step response (e.g., confirmation pop), use **`PhaseAnimator`** or **`KeyframeAnimator`** triggered by a discrete `trigger` value so GPU work immediately returns to zero once the gesture finishes.

### C. Isolate High-Frequency Subviews
- Move live clocks, scrubbers, audio meters, or scroll-position readers into dedicated tiny leaf `View` structs.
- Keep `GlassEffectContainer` in a calm sibling/overlay layer whose inputs only change when chrome state genuinely changes.

### D. Protect Bounding Boxes from Rotation / 3D Transforms
- Never animate `.rotationEffect()` or `.rotation3DEffect()` directly on a `.glassEffect()` view—SwiftUI recomputes axis-aligned bounding boxes mid-rotation, distorting capsule curvature and thrashing shaders.
- Rotate only the **inner icon** (`Image(systemName: "plus").rotationEffect(.degrees(isOpen ? 45 : 0))`) while the outer glass circle stays rock-solid.

### E. When to Drop Into UIKit / Core Animation / Metal for Animation
SwiftUI covers ~90% of motion cleanly, but drop to lower-level APIs via `UIViewRepresentable` when profiling proves a bottleneck:
- **Interactive gesture-scrubbed transitions** needing custom interruptible velocity curves (`UIViewPropertyAnimator` + `UIGlassContainerEffect`).
- **1,000+ item scrolling grids** with pinned custom glass chrome (`UICollectionView` + `UIScrollEdgeElementContainerInteraction`).
- **60–120Hz generative/wave/particle graphics** sitting *underneath* glass (`SwiftUI.Canvas` or Metal `MTKView` / `.layerEffect` shaders) so SwiftUI's view graph isn't re-evaluated on every display refresh.

---

## 3. Instruments Profiling Playbook (Verify Before Shipping)

Never guess whether a Liquid Glass animation is smooth—profile on **physical hardware** (Simulator software rendering hides true GPU refraction costs):

1. **SwiftUI Instrument (Xcode Instruments):**
   - Inspect **View Body** updates during scrolling and glass morphs.
   - Red flag: Any `GlassEffectContainer` or toolbar subview re-evaluating continuously during a scroll or timer tick.
2. **Animation Hitches / Core Animation FPS Instrument:**
   - Track **Hitch Time Ratio** (target `< 5 ms/s`, ideally `0 ms/s`) and distinguish **Commit Hitches** (CPU/SwiftUI diff too slow) from **Render Hitches** (GPU refraction/overdraw too heavy).
3. **Xcode View Debugging → Rendering → Flash Updated Regions:**
   - Enable while interacting with the app. Static glass bars should **not** flash continuously when unrelated controls update.
4. **Thermal & Power Check:**
   - Test 60 seconds of active scrolling + morphing on a real iPhone/iPad; confirm zero sustained GPU saturation when the screen is idle.
