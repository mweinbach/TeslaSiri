# The 10 Laws Critique Rubric (Severity-Ranked)

Use this checklist to classify every visual and architectural defect objectively.

---

## Severity 1 — Blockers (Fix Immediately)

1. **Law 1 — Functional Layer Violation:** `.glassEffect()` applied to primary content cards, list rows, reading panes, tables, or operational data blocks.
   - *Fix:* Replace with semantic opaque fill (`.background(.background.secondary, in: ConcentricRectangle())`) or standard content material (`.regularMaterial` / `.thinMaterial` with vibrant labels).
2. **Law 2 — Glass on Flat Static Backdrop:** Glass control sitting over an unchanging solid background with zero scrolling content, photo, map, or atmospheric gradient underneath.
   - *Fix:* Move to an overlay/scroll layer or replace with a crisp solid pill/card.
3. **Law 3 — Multi-Tint Toolbar Chaos:** Two or more buttons in a toolbar/dock painted in competing bright accent tints.
   - *Fix:* Neutral monochromatic glass on secondary controls; reserve `.buttonStyle(.glassProminent)` strictly for ONE primary CTA.
4. **Law 4 — Unreadable `.clear` Over Bright Media:** `.clear` glass placed over daylight photos, snow, sky, or white backgrounds with no contrast backing.
   - *Fix:* Switch to `.regular`, or insert a **35% black dimming scrim** behind the `.clear` HUD.
5. **Law 5 — Missing iOS 27 Bottom Scroll Edge Blur:** Vivid cards or media scrolling directly behind a floating bottom tab bar with default iOS 27 edge behavior (no blur), causing unreadable tab icons/labels.
   - *Fix:* Add `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
6. **Law 8 — Idiom Hardcoding / Broken Resizing:** `UIDevice.current.userInterfaceIdiom` checks or fixed portrait widths that clip on continuous iPadOS windows or resizable iPhone windows.
   - *Fix:* Drive layout via `horizontalSizeClass`, `ViewThatFits`, `NavigationSplitView`, and adaptive grids.
7. **Law 10 — Accessibility Failure:** Missing `accessibilityLabel` on icon-only glass pills, un-gated morph animations ignoring `accessibilityReduceMotion`, low-contrast `quaternaryLabel` / hardcoded grays on materials, or clipped text at large Dynamic Type.
8. **UX Blocker — Broken Flow, Blocking Spinners, or Dead Ends:** Cold-launch permission ambushes, blocking full-screen loading spinners on routine toggles, raw technical error strings (`HTTP 500` / `NSError`), or blank empty states with no recovery action.

---

## Severity 2 — UX Flow, Craft & Polish Issues

9. **UX Flow Friction:**
   - Exposing raw database fields instead of computing the #1 human answer in the `@Observable` model.
   - Using nagging `"Are you sure?"` confirmation alerts for reversible routine deletes/archives instead of an optimistic mutation + transient `.materialize` Undo glass pill.
   - Using full-screen modal sheets when an inset detented half-sheet (`.presentationDetents([.medium, .large])`) or `.inspector` would preserve spatial context.
   - Vague button microcopy (`OK`, `Submit`, `Yes`) instead of clear action verbs (`Archive Flight`, `Save Preset`).
10. **Law 6 — Sloppy Toolbar Grouping:**
    - Mixing text-labeled buttons and icon-only buttons in one shared glass pill (add `ToolbarSpacer(.fixed)`).
    - Avatar/photo trapped in an unwanted glass capsule (add `.sharedBackgroundVisibility(.hidden)`).
    - Conditional view hidden *inside* `ToolbarItem` leaving an empty ghost glass bubble (hide the entire `ToolbarItem`).
11. **Law 7 — Broken Concentricity & Legacy Rhythm:**
    - Mismatched hardcoded `RoundedRectangle(cornerRadius:)` nested inside sheets/bezel curves (switch to `ConcentricRectangle`).
    - Legacy `ALL CAPS` section headers instead of `Title Case`.
    - Manual `.shadow(radius:)` or `.stroke(.white.opacity(0.25))` fighting iOS 27's native crisp borders and lighter dark-mode glass.
12. **Law 9 — Typographic & Numeral Sloppiness:**
    - Live clocks, flight times, prices, or metric tables missing `.monospacedDigit()`.
    - Overcrowded cards with unnecessary divider lines where spacing and font weight should separate information.

---

## Severity 3 — Performance & Engineering Hygiene

13. **Unbatched Glass Siblings:** Multiple neighboring `.glassEffect()` controls without a scoped `GlassEffectContainer`.
14. **Conditional Glass Churn:** `if active { .glassEffect() }` instead of `.glassEffect(active ? .regular : .identity)`.
15. **Unsafe Transforms on Glass:** `.rotationEffect()` or `.repeatForever()` applied directly on a `.glassEffect()` surface.
16. **Fake Gesture Controls:** `.onTapGesture` on `Image` instead of `Button` with `.glass` / `.interactive()`.
17. **iOS 27 `@State` Macro Misuse:** Mutating `@State` inside `init` before `self` initialization.
18. **Legacy Opt-Out Reliance:** Dead `UIDesignRequiresCompatibility` Info.plist keys or solid `UINavigationBarAppearance` backgrounds left over from iOS 18/26.
