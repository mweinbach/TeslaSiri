# iOS 26 → iOS 27 & iPadOS 27 Visual and Behavioral Deltas

WWDC 2026 did not discard Liquid Glass—it **hardened legibility, added continuous user control, and made native adoption mandatory**. Audit every iOS 26 design or codebase against the 9 concrete shifts below.

---

## 1. Mandatory Adoption (Opt-Out Removed)
- **iOS 26:** Developers could set `UIDesignRequiresCompatibility` in `Info.plist` to keep legacy iOS 18 bar/control styling.
- **iOS 27 (Xcode 27 SDK):** That opt-out key is ignored. All native `TabView`, `NavigationStack`, `Toolbar`, `Sheet`, and UIKit bars render in Liquid Glass automatically.
- **Action:** Strip legacy `UINavigationBarAppearance` / `UITabBarAppearance` opaque background overrides and custom blur backdrop hacks immediately.

## 2. Perimeter Borders Replace Diffuse Drop Shadows (Light Surfaces)
- **Visual reference:** [screenshots/ios27-borders-vs-shadow.jpg](./screenshots/ios27-borders-vs-shadow.jpg)
- **Change:** On pure white or very bright canvases, iOS 26 floating pills looked hazy because they relied on soft drop shadows. iOS 27 uses crisp, subtle perimeter borders paired with sharper specular rim highlights.
- **Action:** Do not add manual `.shadow(radius: 12)` hacks around `.glassEffect()` views to "make them pop" on white—it fights iOS 27's crisp edge rendering.

## 3. Lighter Dark-Mode Glass & Active Tab Pill Inversion
- **Visual reference:** [screenshots/ios27-dark-glass-tabbar.jpg](./screenshots/ios27-dark-glass-tabbar.jpg)
- **Change:** Dark-mode Liquid Glass containers (tab bars, toolbars, dark bottom sheets) are visibly lighter and more frosted in iOS 27.
  - Because the dark tab bar container is lighter, the **active tab selection pill flips from a lighter capsule (iOS 26) to a darker capsule (iOS 27)** to maintain contrast.
  - Dark-mode bottom sheets let colorful backdrops (like maps) bleed visibly through, and small top-right `X` close buttons sit inside a distinct circular glass pill instead of nearly disappearing.
- **Action:** Re-inspect every custom dark-mode sheet background and dark-mode glass border. Avoid hardcoded `.stroke(.white.opacity(0.25))`—let system Liquid Glass draw borders dynamically.

## 4. Continuous System Transparency Slider (`Ultra Clear` ↔ `Fully Tinted`)
- **Visual reference:** [screenshots/ios27-clear-vs-tinted-slider.jpg](./screenshots/ios27-clear-vs-tinted-slider.jpg)
- **Change:** Replaces the binary `Clear` / `Tinted` toggle in Settings with a continuous slider allowing users to choose anything from near-transparent refraction to high-opacity milky tinting.
- **Action:** Always use native `.glassEffect(...)` and `.buttonStyle(.glass)` APIs so your custom controls automatically respect the user's slider position. Test both extremes in Xcode 27 Device Hub / Settings.

## 5. Prominent Colored Button Contrast Fix
- **Change:** On iOS 26, bright colored prominent buttons (e.g., orange/yellow confirmation checkmarks) rendered dim translucent foreground symbols. On iOS 27, `.buttonStyle(.glassProminent)` renders crisp, bright white foreground glyphs/labels by default.
- **Action:** Remove iOS 26 workarounds that manually layered opaque colored circles behind prominent toolbar buttons.

## 6. Scroll Edge Effects Default Reversal (Top & Bottom)
- **Visual references:**
  - Top bar: [screenshots/ios27-scroll-edge-top.jpg](./screenshots/ios27-scroll-edge-top.jpg)
  - Bottom tab bar: [screenshots/ios27-scroll-edge-bottom.jpg](./screenshots/ios27-scroll-edge-bottom.jpg)
- **Change:**
  - **Top navigation bar:** Defaults to a **non-gradient hard blur with a horizontal bottom hairline border** (closer to iOS 18 legibility) instead of iOS 26's soft gradient fade.
  - **Bottom tab bar:** Defaults to **no bottom scroll edge blur/fade**, allowing high-contrast cards and photos to scroll sharply behind translucent tab pills.
- **Action:** Whenever colorful cards, media grids, or dense text scroll behind a bottom floating tab bar, explicitly opt into `.scrollEdgeEffectStyle(.soft, for: .bottom)`. (If you prefer soft fading at the top as well, explicitly set `.scrollEdgeEffectStyle(.soft, for: .top)`.)

## 7. `TabRole.prominent` for Detached Primary Actions
- **Visual reference:** Notice the trailing `+` glass circle in [screenshots/ios27-scroll-edge-bottom.jpg](./screenshots/ios27-scroll-edge-bottom.jpg).
- **Change:** iOS 26 only allowed `Tab(role: .search)` to separate into its own trailing circular glass pill. iOS 27 introduces **`Tab(role: .prominent)`** so any primary destination/action (Create `+`, Cart, Compose) detaches natively beside the floating tab capsule.
- **Action:** Replace brittle `ZStack` overlay FABs positioned manually next to `TabView` with native `Tab(role: .prominent)` whenever the action belongs at top-level navigation.

## 8. Universal Swipe Actions, Reordering & Toolbar Minimization
- **Swipe outside `List`:** `.swipeActionsContainer()` unlocks native circular glass/tinted swipe action buttons on `LazyVStack`, `LazyVGrid`, and custom scrollable card layouts.
- **Declarative reordering:** `.reorderContainer(for:move:)` + `.reorderable()` replace manual drag gestures and `IndexSet` boilerplate outside `List`.
- **Toolbar auto-minimization:** `.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` complements `.tabBarMinimizeBehavior(.onScrollDown)`.

## 9. Resizable iPhone Apps & Landscape Sidebar
- **Change:** iPhone apps can run in resizable windows (iPad hosting, iPhone Mirroring, multi-pose hardware) and can transition to an **iPadOS-style floating left glass sidebar in landscape** when adopting `.tabViewStyle(.sidebarAdaptable)`.
- **Action:** Never hardcode portrait phone widths or branch layout logic on `UIDevice.current.userInterfaceIdiom`. Always drive layout from `horizontalSizeClass`, `verticalSizeClass`, and local container bounds.
