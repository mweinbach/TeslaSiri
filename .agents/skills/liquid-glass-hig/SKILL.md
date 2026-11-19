---
name: liquid-glass-hig
description: >-
  Provides Apple's official Human Interface Guidelines for Liquid Glass and every critical visual and behavioral change from iOS 26 to iOS 27 and iPadOS 27.
  Use when deciding between Regular and Clear glass variants, configuring tinting, scroll edge effects, concentric geometry, dark-mode contrast, Icon Composer assets, or auditing compliance with iOS 27's mandatory Liquid Glass rules and global transparency slider.
---

# Liquid Glass Human Interface Guidelines (iOS 26 → iOS 27)

Liquid Glass is Apple's live optical material layer for navigation and controls across iOS, iPadOS, macOS, watchOS, tvOS, and visionOS. Unlike legacy static frosted blurs, Liquid Glass dynamically refracts underlying content (lensing), renders edge specular highlights, adapts foreground ink luminance automatically, and responds to user-selected transparency settings.

## Core HIG Layering Rules

1. **Functional Layer Only:** Liquid Glass sits *above* app content exclusively for controls and navigation—tab bars, sidebars, toolbars, floating action buttons, sheets, popovers, and transient HUDs.
2. **Never Apply Liquid Glass to Content:** Do not put `.glassEffect()` on app backgrounds, list rows, editorial cards, or tables. Inside the content layer, use opaque semantic surfaces or standard materials (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`) paired with system vibrant foreground styles.
   - *Exception:* Controls inside content (such as sliders and toggles) transiently adopt Liquid Glass while actively dragged or interacted with.
3. **Use Native Controls First:** Standard SwiftUI and UIKit navigation/control components adopt Liquid Glass automatically when compiled against the iOS 26/27 SDK. Remove legacy opaque bar background hacks (`UINavigationBarAppearance`, custom tinted rectangles) so system refraction and scroll edge effects work properly.
4. **No Opt-Out in iOS 27:** The temporary `UIDesignRequiresCompatibility` Info.plist bypass from iOS 26 is **ignored when compiling with Xcode 27 / iOS 27 SDK**. Every native component renders in Liquid Glass automatically.

## Critical iOS 26 → iOS 27 Visual Shifts

Designers and agents trained on iOS 26 assumptions will ship contrast and scroll bugs on iOS 27 unless they account for these verified changes. Read [references/ios27-deltas.md](./references/ios27-deltas.md) and inspect the visual comparison screenshots in [references/screenshots/INDEX.md](./references/screenshots/INDEX.md):

- **Defined Borders Replace Hazy Shadows:** On light/white backgrounds, iOS 27 defines glass pills and circular buttons with crisp subtle perimeter borders rather than heavy diffuse drop shadows.
- **Lighter Dark-Mode Glass & Inverted Tab Selection:** Dark-mode glass containers and bottom sheets are noticeably lighter and more translucent in iOS 27. Consequently, the active tab selection pill flips from *lighter* (iOS 26) to **darker** (iOS 27), and sheet close `X` buttons sit inside visible circular glass pills. Re-check custom dark sheet tint colors for contrast.
- **Global Transparency Slider (`Ultra Clear` ↔ `Fully Tinted`):** Replaces the binary iOS 26 Clear/Tinted toggle. Every native component scales opacity dynamically along this continuous range; never design custom overlays assuming a single fixed translucency.
- **Prominent Button Contrast Fixed:** Colored prominent glass buttons (`.buttonStyle(.glassProminent)`) now render crisp, high-contrast white icons/labels rather than dim translucent glyphs.
- **Scroll Edge Defaults Changed (Major Gotcha):**
  - *Top navigation bars* switched from iOS 26's soft gradient blur to a **non-gradient hard blur with a subtle bottom hairline** by default.
  - *Bottom tab bars* have **no default bottom scroll edge fade** in iOS 27, letting colorful cards collide harshly behind floating tab pills. Explicitly apply `.scrollEdgeEffectStyle(.soft, for: .bottom)` whenever rich cards or photos scroll underneath a bottom tab bar.
- **New Native Structural Primitives:** `Tab(role: .prominent)` breaks any key action (e.g., `+`, Cart) out into a separate trailing glass circle beside the tab pill; iPhones gain an adaptive landscape left sidebar; swipe actions and reordering work natively outside `List`.

## Variant, Tint, Geometry & Icon Quick Rules

- **Regular vs. Clear + 35% Dimming Rule:** Use `.regular` by default for any text-heavy or noisy-background chrome. Use `.clear` *only* over rich media (photos, video, maps) — and add a **35% dark dimming scrim** behind `.clear` controls whenever underlying media is bright. Full matrix in [references/variants-and-tinting.md](./references/variants-and-tinting.md).
- **Tint Sparingly:** Keep secondary toolbar pills monochromatic; apply accent tint strictly to the single primary action button's background (e.g., Done checkmark) or selected tab item. Never tint every button in a toolbar.
- **Concentricity & Layout Polish:** Match nested corner radii mathematically via `ConcentricRectangle` / `UICornerConfiguration`. Use Title-Style Capitalization on section headers, taller grouped list rows, inset half-sheets, and inline source-anchored confirmation dialogs (`confirmationDialog` / action sheets).
- **App Icons (Icon Composer):** Build multi-layered refractive icons (foreground, middle, background) supporting Default, Dark, Clear, and Tinted modes. See [references/icon-composer-spec.md](./references/icon-composer-spec.md).
