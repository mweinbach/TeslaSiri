# SwiftUI iOS 26 & iOS 27 Liquid Glass API Cheatsheet

All APIs below are verified against iOS 26 / iOS 27 SDK documentation. Always wrap iOS 26/27-only modifiers in `#available(iOS 26, *)` / `#available(iOS 27, *)` when supporting earlier deployment targets.

---

## 1. Core Liquid Glass Modifiers (iOS 26+)

```swift
// Primary glass modifier (defaults: .regular, shape: Capsule)
func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape,
    isEnabled: Bool = true
) -> some View

// Glass configuration chain
Glass.regular                       // Default adaptive frosted/refractive glass
Glass.clear                         // High-translucency media overlay (add 35% dark scrim on bright media)
Glass.identity                      // No glass rendered; preserves view tree identity for smooth toggling
Glass.regular.tint(.orange)         // Tinted glass (use sparingly for primary emphasis)
Glass.regular.interactive()         // Enables touch/pointer lensing & specular highlights
Glass.regular.tint(.blue).interactive()

// Standard button styles (prefer over raw .glassEffect on Buttons)
.buttonStyle(.glass)
.buttonStyle(.glassProminent)       // Single primary CTA; crisp white glyph/label in iOS 27
```

**Modifier Order Rule:**
```swift
// ✅ CORRECT: Frame, padding, and foreground BEFORE .glassEffect
Label("Filter", systemImage: "line.3.horizontal.decrease")
    .font(.subheadline.weight(.medium))
    .padding(.horizontal, 14)
    .frame(height: 40)
    .glassEffect(.regular.interactive(), in: .capsule)

// ❌ WRONG: Padding AFTER .glassEffect shrinks the glass tight around raw text
Label("Filter", systemImage: "line.3.horizontal.decrease")
    .glassEffect(.regular.interactive(), in: .capsule)
    .padding(.horizontal, 14)
```

---

## 2. Containers, Grouping & Morphing (iOS 26+)

```swift
// Batches GPU passes and enables fluid merging/morphing within `spacing` points
GlassEffectContainer(spacing: 16) { ... }

// Coordinates morph identity across view state transitions
.glassEffectID("actionID", in: namespace)

// Merges separate subviews into one continuous glass shape pool
.glassEffectUnion(id: "groupID", namespace: namespace)

// Controls insertion/removal transition behavior
.glassEffectTransition(.matchedGeometry) // Morphs shape smoothly within container
.glassEffectTransition(.materialize)     // Fades glass material cleanly without geometric stretch
.glassEffectTransition(.identity)        // Instant state snap
```

---

## 3. Toolbars, Tabs, Accessories & Scroll Edges (iOS 26 & iOS 27)

```swift
// Toolbars
ToolbarSpacer(.fixed, placement: .topBarTrailing)     // Splits adjacent items into distinct glass pills
ToolbarSpacer(.flexible, placement: .bottomBar)       // Pushes pill clusters to opposite ends
.sharedBackgroundVisibility(.hidden)                  // Removes shared glass backing (e.g., user avatar)
.safeAreaBar(edge: .bottom) { ... }                   // Pinned custom chrome participating in scroll edge effects

// Tabs & Accessories
Tab(value: "search", role: .search) { ... }           // Detached trailing search glass pill (iOS 26+)
Tab(value: "create", role: .prominent) { ... }        // NEW iOS 27: Detached trailing primary action pill
.tabViewStyle(.sidebarAdaptable)                      // Adapts into iPadOS sidebar & iPhone landscape sidebar
.tabBarMinimizeBehavior(.onScrollDown)                // Collapses bottom tab pill while scrolling down
.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar) // NEW iOS 27: bar minimization
.tabViewBottomAccessory(isEnabled: isPlaying) { ... } // Persistent accessory (e.g., mini-player)
@Environment(\.tabViewBottomAccessoryPlacement) var placement // .expanded vs .inline

// Scroll Edge Effects (CRITICAL in iOS 27!)
.scrollEdgeEffectStyle(.soft, for: .bottom)           // Restores soft edge blur behind bottom tab pills
.scrollEdgeEffectStyle(.hard, for: .top)              // Crisp blur + hairline divider
.scrollEdgeEffectStyle(.automatic, for: .all)         // System default
```

---

## 4. Concentric Geometry, iPadOS & iOS 27 Non-List Interactions

```swift
// Concentric corner geometry (matches parent container / sheet / bezel automatically)
.background(.background.secondary, in: ConcentricRectangle())
.clipShape(ConcentricRectangle())

// iPadOS immersion & multi-window awareness
.backgroundExtensionEffect(isEnabled: true)           // Mirrors & blurs hero art behind sidebars/inspectors
.inspector(isPresented: $showInspector) { ... }       // Trailing glass inspector column
@Environment(\.appearsActive) private var appearsActive // Dim/quiet custom chrome when window is inactive

// NEW iOS 27: Swipe actions & drag-to-reorder outside List (LazyVStack / LazyVGrid)
ScrollView {
    LazyVStack(spacing: 12) {
        ForEach(items) { item in
            ItemCard(item: item)
                .swipeActions {
                    Button("Delete", role: .destructive) { delete(item) }
                }
        }
        .reorderable()
    }
}
.swipeActionsContainer()
.reorderContainer(for: Item.self) { difference in
    items.apply(difference: difference)
}
```

---

## 5. Backwards Compatibility Pattern (`#available`)

When supporting iOS 18 alongside iOS 26/27, isolate glass modifiers into a tiny view extension so feature views stay readable:

```swift
extension View {
    @ViewBuilder
    func adaptiveGlassCapsule(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            let style: Glass = interactive ? .regular.interactive() : .regular
            self.glassEffect(style, in: .capsule)
        } else {
            self.background(.regularMaterial, in: Capsule())
        }
    }
}
```
