# App Icons & Icon Composer Specification (iOS 26 / iOS 27)

iOS 26 and iOS 27 retired flat, single-bitmap app icons in favor of **multi-layered, optically refractive Liquid Glass icons** authored in Apple's **Icon Composer** tool.

---

## 1. Structural Architecture: 3 Distinct Layers

Instead of baking drop shadows, gloss gradients, or static highlights into a flat PNG, provide **clean, simplified vector/raster layers** and let the OS render real-time light refraction, tilt-responsive specular edges, and depth shadows:

1. **Background Layer:** Solid color, subtle atmospheric gradient, or calm texture anchored to the updated concentric icon grid (rounded rectangle on iOS/iPadOS/macOS; circular on watchOS).
2. **Middle Layer:** Primary symbolic shape or translucent geometric form (can use semi-transparency so background tones softly refract through it).
3. **Foreground Layer:** Focal emblem, crisp glyph, or highlight accent that floats slightly forward with subtle parallax/specular separation.

---

## 2. Four Required Appearance Variants

Every iOS 27 app icon must look intentional across **all four** user-selectable Home Screen modes—test every variant in Icon Composer before shipping:

| Variant | System Behavior | Design Guidance |
| :--- | :--- | :--- |
| **Default (Light)** | Full color, crisp specular rim, subtle layered shadows | Keep silhouette clean and recognizable at 29pt (Settings/Spotlight) as well as Home Screen size |
| **Dark** | Deepened background surface with luminous foreground layers | Avoid pure `#000000` flat voids; keep foreground shapes vibrant enough to read clearly against dark wallpapers |
| **Clear (Liquid Glass)** | Translucent refractive glass icon showing wallpaper colors behind it | Rely on distinct layer contrast and clean alpha cutouts—busy fine-line details turn muddy in Clear mode |
| **Tinted** | System applies the user's chosen monochromatic wallpaper tint across layers | Ensure foreground/middle/background layers have strong **luminance separation** (not just hue contrast), otherwise monochrome tinting collapses the icon into one flat shape |

---

## 3. Common Icon Mistakes to Avoid

- ❌ Baking static glossy streaks or fake drop shadows into layer artwork (clashes with dynamic OS specular highlights).
- ❌ Using text, intricate photographic scenes, or hair-thin strokes that vanish in Clear or Tinted modes.
- ❌ Relying purely on color hue differences (e.g., red shape on green background of equal brightness) without luminance contrast—totally breaks in Tinted and Clear modes.
- ❌ Exporting a legacy flattened `AppIcon.appiconset` PNG without verifying how iOS 27 auto-glassifies it across Dark, Clear, and Tinted Home Screens.
