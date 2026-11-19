# Pure SwiftUI First — and When Embedding UIKit / Core Text / Metal Wins

Build with **pure SwiftUI by default**. SwiftUI gives you native Liquid Glass, automatic iOS 27 transparency slider scaling, `GlassEffectContainer` morphing, and dramatically faster iteration.

However, shipping truly *Flighty*- or *Overcast*-grade iOS software means recognizing the exact places where SwiftUI's abstraction leaks or drops below 120Hz—and embedding a surgical UIKit, Core Text, or Metal island via `UIViewRepresentable` / `UIViewControllerRepresentable`.

---

## Decision Matrix: Keep Pure SwiftUI vs. Embed UIKit / Lower-Level Tech

| Scenario | Recommended Tech | Why |
| :--- | :--- | :--- |
| Standard screens, settings, detail sheets, forms, floating toolbars, <500-item feeds | **Pure SwiftUI** | Native Liquid Glass adoption, clean `@Observable` state, minimal glue code |
| Very large, heterogeneous, or rapidly mutating feeds/grids (1,000+ rich media/telemetry cells with strict 120Hz scrolling) | **UIKit `UICollectionView` (`UIViewRepresentable`)** + `NSDiffableDataSourceSnapshot` | True cell recycling, prefetching (`UICollectionViewDataSourcePrefetching`), predictable memory ceilings, zero SwiftUI lazy-stack identity jitter |
| Custom floating chrome requiring rock-solid scroll-edge coordination or working around an OS tab-bar accessory bug (*Overcast* pattern) | **UIKit `UIVisualEffectView(effect: UIGlassEffect())`** + **`UIScrollEdgeElementContainerInteraction`** | Direct control over interactive gestures, safe-area inset math, and exact UIKit scroll edge registration |
| Multi-element UIKit glass cluster that needs shared GPU batching & morphing | **UIKit `UIVisualEffectView(effect: UIGlassContainerEffect())`** | Exact UIKit equivalent of `GlassEffectContainer`; put child `UIVisualEffectView(effect: UIGlassEffect())` views inside `contentView` and tune `containerEffect.spacing` |
| Rich custom text editing, syntax highlighting, multi-cursor selection | **UIKit `UITextView` (TextKit 2)** | Deterministic selection rects, keyboard accessory bars, and typing latency |
| Liquid Glass rendered *inside* custom display typography outlines (*Return* timer digits) | **Core Text (`CTLine` → `CTFontCreatePathForGlyph` → `CGPath`)** wrapped in SwiftUI `Shape` | SwiftUI `Text.foregroundStyle(.thinMaterial)` only gives legacy static blur, not optical Liquid Glass refraction; extracting a `CGPath` lets you pass it to `.glassEffect(.clear, in: textShape)` |
| Real-time generative atmospheric skies, custom fluid wave charts, or audio visualizers | **SwiftUI `Canvas` / Metal (`MTKView` or `.colorEffect` / `.layerEffect` Metal shaders)** | Keeps per-frame rendering off the main SwiftUI diffing loop and strictly on the GPU |

---

## Verified UIKit Liquid Glass APIs (iOS 26 / iOS 27)

Use the real Apple UIKit classes—never invent wrapper names:

- **`UIGlassEffect`** (subclass of `UIVisualEffect`):
  - Initialized with style (`.regular`, `.clear`); properties `tintColor: UIColor?`, `isInteractive: Bool`.
  - Hosted inside a standard **`UIVisualEffectView(effect: glassEffect)`**.
- **`UIGlassContainerEffect`** (subclass of `UIVisualEffect`):
  - Property `spacing: CGFloat` controls proximity merging/morphing distance.
  - Hosted inside a parent **`UIVisualEffectView(effect: containerEffect)`**; add child glass `UIVisualEffectView`s into `parent.contentView`.
- **`UIButton.Configuration`:** `.glass()`, `.prominentGlass()`, `.clearGlass()`, `.prominentClearGlass()`.
- **`UICornerConfiguration` / `view.cornerConfiguration`:** Concentric corner radius matching UIKit equivalents of `ConcentricRectangle`.
- **`UIScrollEdgeElementContainerInteraction`:** Registers custom UIKit floating bars/controls with scroll views for native scroll-edge effects.
- **`UIBackgroundExtensionView`:** UIKit equivalent of `.backgroundExtensionEffect()` behind split-view sidebars and inspectors.

---

## Golden Rules for Clean SwiftUI ↔ UIKit Bridging

1. **Never Recreate the UIKit View on State Updates:** Keep `makeUIView` lightweight and push incremental updates in `updateUIView` via `NSDiffableDataSourceSnapshot` or property diffs (comparing before setting!).
2. **Keep Content Cells Opaque:** Inside a bridged `UICollectionView`, do **not** put an individual `UIGlassEffect` inside every scrolling cell—that violates the Functional Layer HIG law *and* multiplies GPU backdrop passes. Put glass only on floating overlays or grouped container bars.
3. **Bridge Safe Areas & Scroll Edges Cleanly:** Let SwiftUI manage outer navigation/sheets while the `UIViewRepresentable` fills edge-to-edge (`ignoresSafeArea()` only when explicitly handling `contentInset` / `additionalSafeAreaInsets`).
4. **Core Text `CGPath` Y-Flip Rule:** Core Text uses a bottom-left origin while SwiftUI `Path` uses top-left. Always apply `CGAffineTransform(scaleX: 1, y: -1)` and recenter `boundingRect` inside `rect` when converting glyph paths into a `Shape` for `.glassEffect`. Also use fixed-width digit frames (`fontSize * 0.6`) because `.monospacedDigit()` does not apply to a custom `Shape`.
