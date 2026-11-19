# iOS 27 & iPadOS 27 Pre-Ship Verification Matrix

Run through this matrix using **Xcode 27 Previews**, **Xcode 27 Device Hub**, and at least one **physical iPhone / iPad** before signing off on any release.

---

## 1. System Visual & Appearance Matrix

| Axis | Test States | What to Verify |
| :--- | :--- | :--- |
| **iOS 27 Transparency Slider** | **Ultra Clear** (far left) AND **Fully Tinted** (far right) | Controls remain legible at Ultra Clear over busy scrolling feeds; labels/icons don't lose hierarchy or wash out at Fully Tinted |
| **Color Scheme** | **Light Mode** (pure white + colorful hero) AND **Dark Mode** | Crisp native borders on white (no hazy double shadows); dark-mode custom sheets stay legible despite iOS 27's lighter dark glass; active tab pill contrast holds |
| **Scroll States** | At rest (top), mid-scroll over text, mid-scroll over vivid images/cards | Top nav edge stays clean; bottom tab bar uses `.scrollEdgeEffectStyle(.soft, for: .bottom)` so vivid cards never obscure tab icons |
| **App Icon (Icon Composer)** | **Default**, **Dark**, **Clear**, **Tinted** | Silhouette and luminance separation stay crisp across all 4 Home Screen modes at both Home Screen and 29pt Settings scale |

---

## 2. Accessibility Matrix

| Setting | Expected Behavior |
| :--- | :--- |
| **Reduce Transparency** | Custom glass surfaces degrade cleanly to readable high-contrast opaque/frosted fallbacks with zero invisible borders or white-on-white glyphs |
| **Increase Contrast** | Foreground text, secondary labels, and semantic badges pass contrast without fading into backgrounds |
| **Reduce Motion** | `GlassEffectContainer` morphs degrade cleanly to `.identity` / simple cross-fades; zero dizzying lensing stretches or spring bounces |
| **Dynamic Type (`Default` → `AX3`)** | Metric rows reflow cleanly (vertical fallback via `ViewThatFits`); floating toolbar pills and sheet headers never overlap or truncate primary labels |
| **VoiceOver** | Every icon-only glass pill has a clear `accessibilityLabel` and `Button` trait; decorative mirror reflections or background layers have `.accessibilityHidden(true)` |

---

## 3. Adaptive Layout & Multi-Window Matrix (iOS 27 + iPadOS 27)

- [ ] **iPhone Portrait (Compact):** Floating bottom tab pill, detached `.search` / `.prominent` actions, inset half-sheets, and bottom-anchored search/accessories.
- [ ] **iPhone Landscape:** Sidebar adaptation (if using `.sidebarAdaptable`) and comfortable vertical scrolling without clipped toolbars.
- [ ] **iPadOS Narrow Window (~360pt wide):** Collapses cleanly to compact layout without overlapping columns or clipped cards.
- [ ] **iPadOS Medium & Wide Continuous Resize:** Drag window corner continuously across widths—bento grids reflow smoothly, floating glass sidebar & inspector dock cleanly, `.backgroundExtensionEffect()` fills behind chrome cleanly.
- [ ] **iPadOS Inactive Window (`appearsActive == false`):** Chrome softens gracefully; system menu bar shortcuts work when focused.

---

## 4. Physical Hardware Performance Audit (Instruments)

- [ ] **SwiftUI Instrument:** Zero continuous `View.body` invalidations on `GlassEffectContainer` or toolbars during scrolling or idle timers.
- [ ] **Animation Hitches / Core Animation FPS:** Smooth 120Hz scrolling and morph transitions with Hitch Time Ratio near `0 ms/s`.
- [ ] **Xcode View Debugging → Flash Updated Regions:** Static glass navigation bars do not flash repeatedly during unrelated updates.
- [ ] **Hybrid Decision Check:** If any massive feed, scrubber, or custom canvas fails to hold 120Hz after SwiftUI optimization, apply the UIKit (`UICollectionView` / `UIGlassContainerEffect`) or Metal/Canvas bridge from `swiftui-liquid-glass`.
