# Liquid Glass Variants, Tinting, Vibrancy & Concentricity

## 1. Choosing Between `.regular` and `.clear`

| Variant | Optical Behavior | When to Use | Legibility Guardrail |
| :--- | :--- | :--- | :--- |
| **`.regular`** *(Default)* | Blurs and dynamically shifts background luminosity (dark slate haze on dark scenes, soft warm ivory on bright scenes) with a crisp specular rim | **Default everywhere**: navigation bars, tab bars, sidebars, alerts, popovers, toolbars, text-bearing floating pills, and controls over scrolling text or mixed backgrounds | Automatically flips symbols/labels between dark and light ink; pair with `.scrollEdgeEffectStyle(.soft, for: .bottom)` over vivid card grids on iOS 27 |
| **`.clear`** | Minimal optical diffusion so rich textures, photos, or video remain visually recognizable through the glass | **Media overlays only**: video players, camera viewfinders, full-bleed photography HUDs, 3D maps/globes, or atmospheric video backgrounds (*Return*, *Moonlitt*) | **The 35% Dimming Rule:** If underlying media can be bright (e.g., daylight sky, white snow, bright photography), place a **dark dimming scrim at 35% opacity** behind `.clear` controls. No scrim needed if the backdrop is guaranteed dark or if using `AVKit` playback controls |
| **`.identity`** | Renders no glass material while preserving view identity in the SwiftUI tree | Toggling glass on/off dynamically without triggering structural view-tree rebuilds | Preferred over `if isGlass { .glassEffect() }` conditionals for 120Hz performance |

---

## 2. Color, Tinting & Vibrancy Do/Don'ts

### Liquid Glass Tinting (Functional Layer)
Liquid Glass has **no inherent color** at rest—it samples ambient hues from whatever scrolls underneath.

- **✅ DO:** Keep secondary toolbar buttons (Back `<`, Close `X`, Share, Markup, Filter) neutral monochromatic glass.
- **✅ DO:** Reserve solid accent tint strictly for **one** primary action per bar/sheet—applying tint to the button's **background** (`.buttonStyle(.glassProminent).tint(.accentColor)` or `.glassEffect(.regular.tint(.blue).interactive())`), or to the selected tab bar item.
- **❌ DON'T:** Tint every button in a toolbar pill blue/orange/purple—it destroys hierarchy and creates visual glare.
- **❌ DON'T:** Match icon/label color to a colorful background underneath; prefer neutral monochromatic chrome over vivid photography or charts.

### Standard Materials Vibrancy (Content Layer)
When using standard materials (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`) inside the **content layer**:
- **✅ DO:** Use semantic vibrant foreground styles (`.primary`, `.secondary`, `.tertiary` / `UIVibrancyEffectStyle.label`, `.secondaryLabel`, `.tertiaryLabel`).
- **❌ DON'T:** Use washed-out grays (`.quaternary` / `systemGray3` / hardcoded low-opacity grays) on `.thinMaterial` or `.ultraThinMaterial`—they fail WCAG contrast over gradients.

---

## 3. Concentric Geometry & Modern HIG Layout Rhythm

Hardware display bezels dictate the curvature language across iOS 26/27 and iPadOS 26/27:

- **Concentric Corner Radii:** Nested rounded elements must share a common geometric center (`innerRadius = max(0, outerRadius - padding)`). In SwiftUI, use `ConcentricRectangle` (or `.clipShape(ConcentricRectangle())` / `.containerShape(.rect(cornerRadius: ...))`) instead of eyeballing arbitrary `RoundedRectangle(cornerRadius: 12)` inside sheets, widgets, and device bezels.
- **Toolbar Grouping Rules:**
  - Adjacent items in a `ToolbarItemGroup` or sequential `ToolbarItem`s share a unified Liquid Glass capsule automatically.
  - Break unrelated groups apart with `ToolbarSpacer(.fixed)` or `ToolbarSpacer(.flexible)`.
  - **Never mix text buttons and icon-only buttons** inside the same shared glass capsule.
  - Strip the shared glass container from non-button visuals (such as circular user avatars) with `.sharedBackgroundVisibility(.hidden)`.
  - Hide entire `ToolbarItem`s conditionally rather than hiding their inner content views—hiding an inner view can leave an orphaned empty glass pill.
- **Sheets, Popovers & Action Sheets:**
  - **Inset half-sheets:** Medium-detent sheets float inset from the display edges so underlying context peeks around their rounded perimeter, smoothly expanding to a more opaque full-height surface when dragged up.
  - **Remove custom popover backgrounds:** Never place manual `UIVisualEffectView` blur layers inside popover content views; popovers supply Liquid Glass natively.
  - **Inline action sheets (`confirmationDialog`):** Originate directly from the triggering button/row (`sourceView` / `sourceItem`) rather than always sliding up from the bottom edge, allowing users to keep interacting with the rest of the screen.
- **Lists & Forms:**
  - Embrace taller default row heights, larger grouped section corner radii, and **Title-Style Capitalization** for section headers (`Flight Details`, not `FLIGHT DETAILS`).
