# Visual Archetypes: Matching Reference Craft to App Function

Great iOS and iPadOS apps do not share one look—they share **total alignment between visual language and functional job**. Use these curated, real-world references to choose the right posture for what you are building.

---

## 1. Editorial Light Utility
**Best for:** Health & wellness, habit tracking, day planners, dictionaries, calm consumer tools.  
**North stars:** *Gentler Streak*, *Structured*, *LookUp*

- **Gentler Streak** (`screenshots/gentler-streak-today.jpg`):
  - **What makes it great:** Pure `#FFFFFF` canvas lets the warm coral mascot, bold editorial greeting (`Hi Katarina, / Great Effort Today`), and emerald `Activity Path` chart own the screen without visual noise.
  - **Glass discipline:** Strictly confined to the floating 4-tab bottom capsule (`Today`, `Health`, `Workouts`, `Insights`), the circular top-right avatar badge, and compact filter pills (`30 days ⌄`). Scrolling `My Day` rows refract softly behind the bottom pill while tab icons remain crisp dark charcoal.
  - **Takeaway:** When an app coaches or calms the user, glass should feel like weightless floating controls over clean paper—never frosted cards stacked on cards.

- **Structured** (`screenshots/structured-iphone-timeline.jpg`):
  - **What makes it great:** Duration-proportional pastel blocks turn an overwhelming schedule into scannable rhythm; quiet inline prompts (`30min of free time?`) turn negative space into a feature instead of adding borders.
  - **Glass discipline:** Bottom 4-tab glass capsule paired with a **detached circular coral `+` FAB** (`Tab(role: .prominent)` pattern in iOS 27), keeping creation effortless without crowding navigation.

- **LookUp:** Pairs vivid editorial `Word of the Day` illustrations under a monochromatic floating glass tab bar while keeping dictionary definitions on high-contrast white reading surfaces.

---

## 2. Operational High-Contrast Telemetry
**Best for:** Travel & aviation, real-time logistics, finance/banking, alerts, mission-critical tools.  
**North stars:** *Flighty*, *Wise*

- **Flighty** (`screenshots/flighty-map-sheet.jpg`, `screenshots/flighty-delay-card.jpg`):
  - **What makes it great:** Relentless clarity under stress. Live departure times, delay predictions (`30m Delay Predicted`), and terminal/gate pills (`↗ F4`, `↗ 20`) are readable in 0.5 seconds in a dim airport terminal.
  - **Glass discipline:** Liquid Glass lives **strictly on the spatial map layer** (floating vertical map-tool capsule on the trailing edge) and sheet header chrome. Every operational flight card uses **opaque high-contrast surfaces** (crisp white in light mode, matte dark charcoal in dark mode) so map coastlines or labels never bleed behind a gate number.
  - **Takeaway:** Never sacrifice operational scannability for translucency. Use semantic color badges (emerald on-time, red late, amber/yellow gate callouts) and tabular numerals relentlessly.

- **Wise (Banking):** Uses the native floating tab bar with intentionally **higher opacity / tinted restraint** rather than ultra-clear glass—reinforcing calm trust for financial numbers.

---

## 3. Atmospheric Dark Optical
**Best for:** Weather, solar/lunar tracking, photography, astronomy, meditation, rich media overlays.  
**North stars:** *Lumy (iOS 27)*, *Moonlitt* (2026 ADA Interaction Winner), *Apple Maps (iOS 27)*, *Return*

- **Lumy — "Lumy with Liquid Glass"** (`screenshots/lumy-split-capsules.jpg`):
  - **What makes it great:** Deep obsidian background warmed by a phase-matched solar horizon glow. The sun arc sits directly above a tactile tick-mark scrubber that feels like a precision camera dial.
  - **Glass discipline:** Top edge corner pills (`Today, 5:08 AM`, grouped `[comment | share]`) and a split 3-part bottom Liquid Glass bar (`[camera] [Tokyo] [sliders]`). Event cards (`Morning Golden Hour`, `Evening Golden Hour`) avoid bright muddy glass and instead use deep translucent surfaces with a crisp `1px` warm specular edge and high-contrast amber tabular times (`4:51 AM`, `5:44 PM`).

- **Moonlitt** (`screenshots/moonlitt-iphone-trio.jpg`):
  - **What makes it great:** Quiet celestial contrast (indigo-violet gradients, deep emerald satellite map, dusk sky camera) with tiny circular glass corner buttons and a single bottom status pill (`Full Moon 100%`) so the 3D lunar arc owns the viewport.

- **Apple Maps iOS 27 Dark Place Sheet** (`screenshots/lumy-apple-maps-sheet.jpg`):
  - **What makes it great:** Smoky translucent detented sheet lets map hues softly tint the surface, reserves bright blue exclusively for the primary `Plan` pill, and nests a compact 3-icon Liquid Glass capsule (`+ | ★ | •••`) over the bottom photo strip so secondary actions stay reachable without expanding the sheet.

- **Return:** Pairs a looped campfire video backdrop (rich motion/color for `.clear` refraction) with Core Text glass timer digits, proving `.clear` glass shines when motion and texture sit underneath.

---

## 4. Dense Multi-Pane & Canvas-First Workspaces
**Best for:** iPadOS dashboards, pro analytics, note-taking, writing, drawing, media catalogs.  
**North stars:** *Tide Guide* (2026 ADA Visuals & Graphics Winner), *Craft*, *Concepts*, *Tot*, *Overcast*, *Sequel*

- **Tide Guide (iPadOS):** Inset floating translucent left sidebar (`Search`, `Today / Overview / Charts / Tables`, station mini-cards), floating top location glass pill, and twilight-navy bento modules with generous inner padding and bold tabular heights/times.
- **Craft** (`screenshots/craft-editorial-cards.jpg`): Warm editorial canvas, clean sidebar, floating top pill view-switchers, and legible bordered document cards. *Caution from design critiques:* Keep translucency out of writing/reading panes—use it strictly on top pills and transient chrome.
- **Concepts (iPadOS):** Unobstructed infinite vector paper (~95% of screen); monochrome floating corner icons and a radial COPIC wheel let the user's artwork own 100% of the color budget.
- **Tot & Overcast:** Models of indie restraint—*Tot* puts whisper-quiet circular glass pills at the top of an uncluttered writing canvas; *Overcast* pairs clean glass action circles with a custom-engineered floating `"Playing now"` bar that delivers silky optical lensing without shipping buggy system workarounds.

---

## 5. Expressive Anti-Chrome Counterpoint
**Best for:** Playful single-purpose apps, tactile instruments, artistic experiences.  
**North stars:** *grug* (2026 ADA Delight & Fun Winner), *(Not Boring) Camera*

- **Takeaway:** Taste is **cohesion and intentionality**, not mandatory conformity. If a focused app builds an entire tactile world (hand-drawn stroke UI or physical camera dials), commit 100% to that material language rather than awkwardly mixing half-hearted custom skins with default chrome.
