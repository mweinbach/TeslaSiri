---
name: swiftui-liquid-glass
description: >-
  Guides production SwiftUI implementation for iOS 26 and iOS 27 Liquid Glass UI, including navigation, toolbars, scroll edges, concentric cards, universal swipe/reorder containers, and pragmatic UIKit/Core Text/Metal interop when SwiftUI hits performance limits.
  Use when writing, refactoring, or debugging SwiftUI views targeting iOS 26/27 or deciding whether to embed UIKit (`UIViewRepresentable`) for smoother scrolling, custom glass containers, or precision typography.
---

# SwiftUI Liquid Glass Implementation (Pure SwiftUI + Pragmatic UIKit Interop)

Default to **pure, idiomatic SwiftUI** for 90% of screens—system bars, sheets, tabs, toolbars, and custom glass pills work best natively and automatically inherit iOS 27's borders, dark-mode contrast, and global Clear ↔ Tinted transparency slider.

At the same time, **never be dogmatic**: when Instruments shows frame drops in 10,000-row rich grids, custom text editors, high-frequency scroll chrome, or glyph-path glass rendering, embedding targeted **UIKit (`UICollectionView`, `UIVisualEffectView` + `UIGlassEffect`, `UIScrollEdgeElementContainerInteraction`)**, **Core Text**, or **Metal** inside SwiftUI yields noticeably superior 120Hz performance and feel.

## Core SwiftUI Workflow

1. **Start with Native System Chrome (Zero Manual Glass Needed):**
   - `TabView` (with `Tab(role: .search)` and iOS 27 `Tab(role: .prominent)`), `NavigationStack`, `NavigationSplitView`, `.toolbar`, `.sheet`, and `.confirmationDialog` all adopt Liquid Glass automatically.
   - Remove legacy opaque bar overrides (`.toolbarBackground(.visible, ...)` with solid fills or `UINavigationBarAppearance` background colors) unless specifically required—they block optical lensing and scroll edge effects.
2. **Apply `.glassEffect()` Strictly to Custom Functional Controls:**
   - Apply **padding, frame, font, and foreground styling BEFORE `.glassEffect(...)`** so the glass capsule wraps the final interactive bounds.
   - Use `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` on standard `Button`s rather than chaining raw `.glassEffect()` manually.
   - Always pass `.interactive()` on custom tappable/focusable glass controls (`Button`, never `.onTapGesture` on `Image`), and wrap adjacent glass controls in a `GlassEffectContainer`.
3. **Configure iOS 27 Scroll Edges & Toolbars Intentionally:**
   - Add `.scrollEdgeEffectStyle(.soft, for: .bottom)` whenever colorful cards or imagery scroll beneath a floating tab bar (iOS 27 defaults to no bottom blur).
   - Separate unrelated toolbar groups with `ToolbarSpacer(.fixed)`; hide glass behind photo avatars with `.sharedBackgroundVisibility(.hidden)`; never mix text and icon-only buttons in the same glass pill.
4. **Use iOS 27 Native Interactions Outside `List`:**
   - Attach `.swipeActionsContainer()` and `.reorderContainer(for:move:)` / `.reorderable()` to `LazyVStack` and `LazyVGrid` instead of writing brittle custom drag/swipe gestures.
5. **Shape Great UX Directly in Your State & Presentation Architecture:**
   - **Anticipatory view models:** Compute human-facing summaries (time remaining, status reason, next urgent action) inside `@Observable` models rather than rendering raw backend fields.
   - **Optimistic & reversible flows:** Update local state immediately on tap with `.sensoryFeedback`, sync asynchronously in `.task`, and surface a transient `.materialize` **Undo** glass pill instead of nagging `"Are you sure?"` alerts for routine deletes/archives.
   - **Spatial continuity:** Prefer `.presentationDetents([.medium, .large])` with `.presentationBackgroundInteraction(.enabled)` over abrupt full-screen modal jumps whenever parent context (maps, timelines, feeds) matters.
   - **Respect the iOS 27 `@State` macro:** Initialize `@State` inline at declaration or update inside `.task` / `.onAppear`—never mutate `@State` in custom `init` before `self` is initialized.
6. **Know When to Bridge UIKit / Core Text / Metal:**
   - Consult [references/uikit-interop-performance.md](./references/uikit-interop-performance.md) before fighting SwiftUI when you hit massive recycled grids, custom floating Now Playing bars, scroll-linked chrome, or glyph-shaped glass.

## Reference & Example Map

- **Verified API signatures & availability guards:** [references/api-cheatsheet.md](./references/api-cheatsheet.md)
- **When & how to embed UIKit / Core Text / Metal inside SwiftUI:** [references/uikit-interop-performance.md](./references/uikit-interop-performance.md)
- **Common implementation bugs & fixes:** [references/common-pitfalls.md](./references/common-pitfalls.md)
- **Complete runnable templates:**
  - [examples/AdaptiveTabShell.swift](./examples/AdaptiveTabShell.swift) — iOS 27 `TabView`, `Tab(role: .prominent)`, `.search`, `.sidebarAdaptable`, `.tabViewBottomAccessory`, `.scrollEdgeEffectStyle(.soft)`
  - [examples/TastefulToolbarAndCards.swift](./examples/TastefulToolbarAndCards.swift) — `ToolbarSpacer`, `.sharedBackgroundVisibility(.hidden)`, single `.glassProminent` CTA, `ConcentricRectangle` matte cards, `.swipeActionsContainer()`, `.reorderContainer()`
  - [examples/OptimisticUXAndUndo.swift](./examples/OptimisticUXAndUndo.swift) — Optimistic mutations, transient `.materialize` Undo glass pill, interactive detented sheet, `ContentUnavailableView` empty state, and non-blocking offline indicator
  - [examples/UIKitHybridGlassBridge.swift](./examples/UIKitHybridGlassBridge.swift) — High-FPS `UIViewRepresentable` wrapping `UICollectionView` + `NSDiffableDataSourceSnapshot` + `UIVisualEffectView(effect: UIGlassEffect())` / `UIGlassContainerEffect`

## Pair With

- **`liquid-glass-animations`** for morphing (`GlassEffectContainer`, `glassEffectID`, `glassEffectUnion`), 120Hz animation performance, and Instruments profiling.
- **`ipados-adaptive-layout`** for multi-window iPadOS layouts, `.backgroundExtensionEffect()`, and system menu bars.
