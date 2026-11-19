# Typography, Color Discipline & Information Density

Visual polish on iOS 27 comes from **quiet structural decisions** far more than shaders or animations. Apply these rules across every screen.

---

## 1. Typography & Numerals

- **Default to San Francisco (SF Pro / SF Rounded / SF Mono) or New York** for editorial pairings (*Craft*-style serif headings + crisp sans body). Avoid arbitrary web fonts unless they define an intentional brand world.
- **Mandatory Tabular Numerals:** Apply `.monospacedDigit()` to **every** clock, countdown, price, flight time, tide height, workout stat, badge count, and table column. Proportional digits cause distracting horizontal jitter during live ticks and destroy vertical column alignment.
- **Title-Style Section Headers (iOS 26/27 HIG):** Use `Title Case` (`Grouped Table View`, `Upcoming Flights`) rather than legacy `ALL CAPS` section labels.
- **Clear 3-Tier Weight Hierarchy:**
  1. **Anchor / Display:** Bold or Semibold primary headline or key metric (`11:40AM`, `Great Effort Today`, `Falling Tide`).
  2. **Primary Body / Row Title:** Regular or Medium `.primary` ink, scannable in one glance.
  3. **Metadata / Context:** `.secondary` ink at `.subheadline` / `.footnote` — never low-contrast washed-out gray (`quaternaryLabel` fails on thin materials).
- **Dynamic Type Readiness:** Use semantic text styles (`.title2`, `.headline`, `.body`, `.subheadline`) and let rows reflow cleanly (e.g., `ViewThatFits` or vertical stack fallback at accessibility sizes) instead of truncating crucial labels.

---

## 2. Color & Tint Discipline

- **The Single-Accent Budget:** Pick **one** primary brand tint per screen context:
  - Applied to: Primary `.glassProminent` action button (e.g., Done checkmark, `Plan`), active tab indicator, or detached creation FAB (`+`).
  - **Never** applied to: Every toolbar button, every card header, or blanket-tinted glass surfaces.
- **Monochromatic Chrome Over Rich Content:** Over photography, maps, or colorful artwork, keep floating glass toolbars and tab bars neutral/achromatic so they inherit ambient color from underneath without clashing.
- **Semantic Status Colors Only Where Earned:** Reserve green (on-time / healthy), amber/yellow (caution / gate callout), and red (delay / destructive) for real data states (*Flighty* pattern), never decorative rainbows.
- **Atmospheric Dark Surfaces Over Pure `#000000` (Where Appropriate):** Pure OLED black works for minimal utilities, but subtle dark charcoal/obsidian (`Flighty`), deep navy (`Tide Guide`), or indigo-violet (`Moonlitt`) lets Liquid Glass specular rims and soft shadows read with realistic depth.

---

## 3. Spacing, Concentricity & Density

- **Roomier iOS 26/27 Rhythm:** Modern Apple lists, grouped forms, and bento modules favor taller rows, generous internal card padding (`16–20pt`), and larger continuous corner radii than iOS 18.
- **Concentric Geometry:** Nested rounded containers must share a geometric center (`outerRadius = innerRadius + padding`). In SwiftUI, prefer `ConcentricRectangle` rather than eyeballing mismatched corner radii inside sheets, cards, and device bezels.
- **Density Matched to Function:**
  - *Calm / Coaching / Reading* (*Gentler Streak*, *Craft*): Low-to-medium density, generous vertical whitespace, one focal chart or card per viewport.
  - *Operational / Telemetry* (*Flighty*, *Tide Guide*): High information density kept calm through strict grid alignment, tabular columns, clear color coding, and zero decorative borders.
- **Make Whitespace Functional:** Follow *Structured*'s lead—use subtle inline indicators (`30min of free time?`) or clean section rhythm instead of drawing boxes around every single item.

---

## 4. Anti-Slop Checklist (Reject Immediately)

- ❌ Glass cards nested inside glass sheets on top of glass backgrounds ("muddy mirrorhouse").
- ❌ Neon purple/cyan gradient blobs behind generic frosted cards ("AI template aesthetic").
- ❌ Heavy drop shadows on cards or buttons (iOS 27 prefers crisp perimeter borders and subtle luminance separation).
- ❌ Mixing icon-only buttons and text-label buttons inside the same floating toolbar glass pill.
- ❌ Crowding 6+ icons into a bottom tab bar or squeezing primary creation buttons into a cramped bar instead of detaching them cleanly.
- ❌ Overriding standard bar backgrounds with solid flat colors that break Liquid Glass refraction and scroll edge behavior.
