---
name: ipados-adaptive-layout
description: >-
  Architects iPadOS 27 and resizable iOS 27 layouts with Liquid Glass floating sidebars, continuous fluid windowing, background extension effects, inspectors, canvas-first toolbars, and the iPadOS system menu bar.
  Use when designing or building iPadOS apps, universal iPhone/iPad apps, split views, multi-window workspaces, keyboard/menu commands, or adapting layouts cleanly across size classes and resizable iPhone windows.
---

# iPadOS 27 & Resizable Adaptive Layout

iPadOS 26 and iPadOS 27 bridge mobile fluidity with desktop-grade windowing: **continuous fluid window resizing**, a **system menu bar**, floating translucent **Liquid Glass sidebars & inspectors**, and resizable iPhone app windows (plus iPhone landscape sidebars). A great iPad app is **never** a stretched iPhone layout—and never a bloated desktop toolbar dump.

From a **user experience** standpoint, large-screen mastery is about **protecting flow state and agency**: keeping secondary details reachable inline via `.inspector(isPresented:)` instead of interrupting work with full-screen modals, letting pointer and keyboard users fly through the app via `.commands`, and letting a workspace stay calm and legible at any continuous window width.

## Core Adaptive Architecture Rules

1. **Size Classes & Local Bounds — Never `userInterfaceIdiom`:**
   - Never branch layouts on `UIDevice.current.userInterfaceIdiom == .pad`. An iPad window resized narrow behaves like compact width, and a resizable iPhone window or iPhone landscape pose can show wide/sidebar layouts.
   - Drive structural transitions from `@Environment(\.horizontalSizeClass)`, `ViewThatFits`, `GridItem(.adaptive(minimum:))`, and `NavigationSplitView` / `.tabViewStyle(.sidebarAdaptable)`.
2. **Choose the Right iPadOS Spatial Pattern for the App's Function:**
   Read [references/spatial-patterns.md](./references/spatial-patterns.md) and visually inspect [references/screenshots/INDEX.md](./references/screenshots/INDEX.md):
   - **Floating Glass Sidebar + Bento Telemetry (*Tide Guide* pattern):** Inset translucent left sidebar (`Search`, top-level sections, recent stations) paired with floating top location pill and calm high-density bento modules.
   - **Two-Column Triage + Workspace (*Structured* / *Craft* pattern):** Persistent list/inbox or folder sidebar paired with a clean opaque scrollable timeline or editorial card grid—never giant frosted panels fighting text.
   - **Canvas-First Floating Controls (*Concepts* / *Moonlitt* pattern):** Leave 90–95% of the iPad display completely unobstructed; tuck tools into slim corner glass clusters, floating pills, or repositionable radial wheels.
3. **Use `.backgroundExtensionEffect()` Behind Sidebars & Inspectors:**
   - For hero photography, maps, sky/ocean backdrops, or rich detail canvases inside `NavigationSplitView`, attach `.backgroundExtensionEffect()` so the system mirrors and blurs adjacent artwork cleanly behind the floating glass sidebar without hiding real UI behind chrome.
4. **Support the iPadOS System Menu Bar & Multi-Window Focus:**
   - Expose all primary commands via SwiftUI `.commands { CommandGroup(...) }` with keyboard shortcuts so iPadOS populates the top system menu bar automatically.
   - Read `@Environment(\.appearsActive)` to subtly quiet custom chrome or pause heavy visual accents when a window loses focus in multi-window mode.
   - See [references/windowing-and-menus.md](./references/windowing-and-menus.md).
5. **Respect iPad vs. iPhone Search & Control Placement:**
   - On iPadOS, keep search in a top-right floating glass pill (or inside the sidebar) with inline suggestions rather than anchoring it to the bottom edge; let `Tab(role: .search)` + `.tabViewStyle(.sidebarAdaptable)` handle the platform shift automatically.

## Reference & Example Map

- **iPadOS spatial archetypes & layout rules:** [references/spatial-patterns.md](./references/spatial-patterns.md)
- **Continuous windowing, menu bar, keyboard shortcuts & focus states:** [references/windowing-and-menus.md](./references/windowing-and-menus.md)
- **Visually verified iPadOS reference screenshots:** [references/screenshots/INDEX.md](./references/screenshots/INDEX.md)
- **Complete runnable SwiftUI template:** [examples/AdaptiveWorkspaceScene.swift](./examples/AdaptiveWorkspaceScene.swift) — `NavigationSplitView`, `.backgroundExtensionEffect()`, `.inspector(isPresented:)`, `.commands` iPadOS menu bar, `@Environment(\.appearsActive)`, and size-class adaptive bento grid
