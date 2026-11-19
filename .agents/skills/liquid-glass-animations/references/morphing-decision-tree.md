# Liquid Glass Morphing Decision Tree & Container Physics

Liquid Glass morphing works via **signed-distance path blending** inside a `GlassEffectContainer`. Mastering the three parameters (`spacing`, `glassEffectID`, `glassEffectUnion`) and three transition modes (`.matchedGeometry`, `.materialize`, `.identity`) is the difference between Apple-grade fluidity and distracting gimmicks.

---

## 1. The Morphing Decision Tree

Ask these three questions in order before writing any morph code:

1. **Do both elements belong to the functional chrome layer (controls, floating pills, HUDs)?**
   - **No** → Do NOT use Liquid Glass or glass morphing. Use standard SwiftUI layout springs or `navigationTransition(.zoom(sourceID:in:))` for content cards.
   - **Yes** → Continue.
2. **Is the entering/changing control a direct spatial child or state mutation of an existing visible glass control nearby (< ~120pt)?**
   - **Yes** → Use **`GlassEffectContainer`** + **`glassEffectID(_:in:)`** + **`.glassEffectTransition(.matchedGeometry)`**.
   - **No** (it appears from nowhere, across the screen, or represents an unrelated system alert/HUD) → Use **`.glassEffectTransition(.materialize)`** paired with `.transition(.opacity.combined(with: .scale(scale: 0.95)))`.
3. **Should two or more distinct subviews visually behave as ONE continuous pool of glass even when laid out separately?**
   - **Yes** → Attach **`.glassEffectUnion(id:namespace:)`** with a shared union ID inside the same `GlassEffectContainer`.
   - **No** → Keep individual `.glassEffect()` capsules and control merge distance purely via `GlassEffectContainer(spacing:)`.

---

## 2. Tuning `GlassEffectContainer(spacing:)`

The `spacing` parameter defines the **magnetic merge threshold** (in points) at which nearby glass shapes start pulling toward each other and liquefying into a shared bridge:

| `spacing` Range | Optical Behavior | Best Use Cases |
| :--- | :--- | :--- |
| **`0` – `10pt`** | Crisp separation until views physically overlap during animation | Independent floating toolbar buttons that only merge momentarily mid-morph |
| **`12` – `24pt`** *(Sweet spot)* | Subtle organic liquid tension as sibling buttons slide out of a FAB or expand | Expanding action clusters (`+` → `Note`, `Photo`, `Scan`), adaptive mini-player docks |
| **`32` – `48pt+`** | Aggressive pooling—adjacent controls fuse into a single continuous glass blob | Deliberately sculpted connected pill clusters or play/scrub control docks |

**Container Scoping Rule:**
- ✅ Scope one `GlassEffectContainer` tightly around a single toolbar, floating dock, or morphing FAB cluster (typically 2–6 glass elements).
- ❌ Never wrap an entire `NavigationStack` or `ScrollView` inside a single `GlassEffectContainer`—every frame checks path proximity across all descendants.

---

## 3. Comparing `glassEffectTransition` Modes

| Mode | Behavior | When to Choose |
| :--- | :--- | :--- |
| **`.matchedGeometry`** | Interpolates shape geometry directly from/to matching `glassEffectID` or nearest container neighbor | Expanding FABs, segmented pill morphs, compact ↔ expanded floating chrome |
| **`.materialize`** | Smoothly crystallizes/dissolves the refractive glass surface in place without warping nearby pills | Transient toast pills, contextual undo bars, camera HUD badges appearing over media |
| **`.identity`** | Zero transition frames—appears/disappears immediately | `accessibilityReduceMotion == true`, instant state swaps, or performance debugging |

---

## 4. `glassEffectID` vs. `glassEffectUnion`

- **`glassEffectID(_:in:)`** tracks **identity across time** (before state → after state). Assign the *same* ID to the outgoing view and incoming view to morph one shape directly into another (e.g., circular icon button morphing into a wide capsule search pill).
- **`glassEffectUnion(id:namespace:)`** merges **geometry across space** (at the same instant). Two separate buttons in an `HStack` with `.glassEffectUnion(id: "media", namespace: ns)` render inside one unified glass outline with shared optical refraction.
- You can combine both on the same view: give each child its own unique `glassEffectID` for individual tracking while sharing a `glassEffectUnion` ID to render them as one grouped pill.

---

## 5. When NOT to Morph (Anti-Patterns)

- ❌ **Long-distance leaps across the screen:** A bottom-right FAB morphing all the way into a top-left navigation button creates an ugly stretched taffy streak across content. Use `.materialize` instead.
- ❌ **Morphing on every scroll tick:** Don't morph glass controls continuously in response to micro-scroll jitter; use hysteretic scroll thresholds or native `.tabBarMinimizeBehavior(.onScrollDown)` / `.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)`.
- ❌ **Rapidly toggling morphs faster than spring settle (~250ms):** Always make animations interruptible via standard SwiftUI spring animations (`withAnimation(.smooth(duration: 0.3))`) rather than linear/ease timers that snap awkwardly when tapped twice quickly.
