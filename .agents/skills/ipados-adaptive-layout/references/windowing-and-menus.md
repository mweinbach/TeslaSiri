# iPadOS 27 Fluid Windowing, Menu Bar & Size-Class Rules

## 1. Continuous Fluid Resizing (Zero Fixed Snap Assumptions)
iPadOS 26/27 windows resize **continuously** down to a minimum size—and iOS 27 iPhone apps can resize flexibly on iPad and via iPhone Mirroring.

- **Ban `UIDevice.current.userInterfaceIdiom` checks for layout.**
- **Use responsive primitives:**
  - `@Environment(\.horizontalSizeClass)` (`.compact` vs. `.regular`) to toggle between single-column/tab navigation and multi-column/inspector layouts.
  - `ViewThatFits(in: .horizontal)` for metric strips and action rows that gracefully stack vertically when a window narrows.
  - `GridItem(.adaptive(minimum: 220, maximum: 360))` for bento dashboards so 4 columns flow seamlessly into 3 → 2 → 1 as the user drags a window corner.
  - `ConcentricRectangle` so inner card radii stay visually harmonious as window bounds and modal detents scale.

## 2. iPhone Landscape Sidebar & Adaptive Tabs
- Adopting `.tabViewStyle(.sidebarAdaptable)` on `TabView` gives you three tailored presentations from one declaration:
  1. **iPhone Portrait / Compact Window:** Floating bottom Liquid Glass tab capsule (+ detached `.search` and iOS 27 `.prominent` pills).
  2. **iPhone Landscape (iOS 27):** Clean adaptive leading glass sidebar (`Edit`, collapsible sections) that frees vertical space.
  3. **iPadOS Regular Width:** Full floating translucent sidebar or compact top/sidebar toggle with native drag-and-drop customization.

## 3. iPadOS System Menu Bar & Keyboard Commands
iPadOS features a first-class top system menu bar. Wire primary actions cleanly through SwiftUI `.commands` on your `WindowGroup` scene so pointer and keyboard users get instant discoverability (plus automatic icons for standard selectors like Cut, Copy, Paste, Share, New):

```swift
WindowGroup {
    AdaptiveWorkspaceScene()
}
.commands {
    CommandGroup(after: .newItem) {
        Button("New Station", systemImage: "plus") {
            createStation()
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
    CommandMenu("View") {
        Button("Toggle Inspector", systemImage: "sidebar.right") {
            toggleInspector()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
}
```

## 4. Multi-Window Active / Inactive State (`appearsActive`)
When multiple windows sit side by side on iPadOS, inactive windows visually recede. Read `@Environment(\.appearsActive)` in custom floating chrome or live visualizations so inactive windows soften accents and avoid competing visually with the focused window:

```swift
@Environment(\.appearsActive) private var appearsActive

// Soften custom highlight or pause subtle shimmer when window loses focus
accentPill
    .opacity(appearsActive ? 1.0 : 0.72)
```

## 5. Window Minimum Sizing & Safe Margins
- Set realistic `.frame(minWidth: 340, minHeight: 420)` on scenes or use `.windowResizability(.contentMinSize)` when appropriate so dense dashboards don't collapse into overlapping text.
- Leave comfortable safe-area breathing room at the top-leading corner of iPadOS windows for system window controls (close/minimize/resize traffic lights).
