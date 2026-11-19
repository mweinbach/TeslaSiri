# iPadOS 27 Spatial Patterns & Visual Benchmarks

Match your iPadOS spatial structure directly to what the user is doing on the large canvas.

---

## Pattern 1: Floating Glass Sidebar + Bento Dashboard
**Benchmark:** *Tide Guide* (2026 Apple Design Award Visuals & Graphics Winner) — see [screenshots/tide-guide-ipad-bento.jpg](./screenshots/tide-guide-ipad-bento.jpg).

- **Structure:** Inset floating translucent left sidebar (`NavigationSplitView`) housing a search field, top-level destinations (`Today`, `Overview`, `Charts`, `Tables`), and collapsible disclosure sections (`Nearby`, `Recents` with compact live metrics).
- **Top Chrome:** Centered floating glass location pill (`Chatham, Stage Harbor ⌄`) + quiet corner actions—no full-width opaque header bar cutting the canvas in half.
- **Content Area:** Calm twilight-navy bento grid (`GridItem(.adaptive(minimum: 220))`) with generous inner card padding (`16–20pt`), crisp `ConcentricRectangle` cards, and tabular numerals. Zero Liquid Glass on the data modules themselves.

---

## Pattern 2: Clean Two-Column Triage + Editor / Timeline
**Benchmark:** *Structured (iPadOS)*, *Craft*

- **Structure:** Persistent leading triage/navigation column (`Inbox` or folder tree) beside a wide, airy primary workspace (`Timeline` or editorial document cards).
- **Restraint Rule:** Do not inflate empty glass chrome just because you have a 13" display. Keep writing, planning, and reading canvases solid and paper-calm, using compact floating pill toolbars at the top edge or a single detached coral/accent `+` action button.
- **Secondary Detail:** Use a trailing **`.inspector(isPresented:)`** panel (floating Liquid Glass sheet on compact widths, docked translucent trailing column on regular widths) for metadata, formatting, or properties instead of pushing modal sheets that obscure the workspace.

---

## Pattern 3: Canvas-First Floating Palette
**Benchmark:** *Concepts* ([screenshots/concepts-ipad-copic.jpg](./screenshots/concepts-ipad-copic.jpg)), *Moonlitt* ([screenshots/moonlitt-multidevice-hud.jpg](./screenshots/moonlitt-multidevice-hud.jpg))

- **Structure:** For drawing, photo/video editing, CAD, maps, or 3D astronomy, **skip permanent sidebars**. Give 90–95% of the display to the canvas.
- **Chrome:** Minimal corner-anchored monochrome glass icon clusters (`undo/redo`, zoom readout, export) and repositionable floating tool wheels or compact bottom status capsules.
- **Apple Pencil Ergonomics:** Place live tactile parameter controls (stroke width, opacity, time scrubbers) directly inside floating radial/pill chrome so artists adjust settings right under the Pencil without opening blocking modal sheets.

---

## Pattern 4: Edge-to-Edge Immersion via `.backgroundExtensionEffect()`

When your detail view features a full-bleed hero image, map, or atmospheric sky inside a `NavigationSplitView`:
- Do **not** draw interactive content behind the sidebar.
- Attach **`.backgroundExtensionEffect()`** to the hero background view. The system automatically mirrors and softly blurs the edge of the hero artwork outward into the safe area behind the floating translucent sidebar and inspector, creating seamless depth while preserving sidebar text contrast.
