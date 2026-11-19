---
name: ios-design-taste
description: >-
  Establishes UX principles, visual taste, restraint, and functional-fit design direction for iOS 27 and iPadOS 27 apps using Liquid Glass.
  Use before designing or building any iOS/iPadOS screen, flow, or component to connect human experience to architecture and code choices, pick the right aesthetic archetype for the app's job, avoid "glassmorphism slop," enforce typography and color discipline, and inspect curated reference screenshots (Flighty, Gentler Streak, Lumy, Structured, Tide Guide, Moonlitt, Craft, Concepts).
---

# iOS 27 & iPadOS Design Taste & User Experience Craft

Great Apple-platform apps are defined by **how they feel to use**—calm under stress, instantaneously responsive, spatially grounded, and unmistakably tailored to their job. Visual craft (Liquid Glass, typography, spacing) only works when it serves **human user experience** and is shaped deliberately in your data model, state flow, and interaction code.

## Step 1: Shape the Experience Before Picking Chrome

Before laying out controls or writing SwiftUI, answer four UX questions (detailed UX-to-code playbook in [references/ux-principles-to-code.md](./references/ux-principles-to-code.md)):

1. **What is the #1 question this screen answers in < 1 second?** Synthesize the human answer in your `@Observable` domain model (e.g., *Flighty*'s `"30m Delay Predicted"` or *Tide Guide*'s `"Low in 2 hr, 54 min"`) instead of dumping raw database fields onto the screen.
2. **What belongs in each disclosure tier?** Keep Tier 1 (the primary canvas) calm and glanceable; move secondary detail to Tier 2 (detented half-sheets, trailing `.inspector`, inline menus, or morphing floating pills) so users stay spatially anchored without modal teleporting.
3. **How will interactions feel instantaneous and reversible?** Favor **optimistic state updates** on frame 1 with subtle `.sensoryFeedback` over blocking spinners, and prefer transient `.materialize` **Undo** pills over nagging `"Are you sure?"` alerts for routine actions.
4. **How do non-ideal states feel?** Design empty (`ContentUnavailableView` with a next step), offline/cached-first, and human-language error recovery states from day one—and ask for permissions only in-context when the user triggers the feature.

## Step 2: Match the Aesthetic Archetype to the App's Function

Never force one visual style onto every product. Identify the app's primary job first, then anchor design decisions to the reference archetype that solves that job best. Read [references/visual-archetypes.md](./references/visual-archetypes.md) for detailed tear-downs, and inspect the bundled screenshots via [references/screenshots/INDEX.md](./references/screenshots/INDEX.md).

| App Job / Function | Archetype | North-Star References | Where Liquid Glass Goes | Content Layer Surface |
| :--- | :--- | :--- | :--- | :--- |
| Daily wellness, habit, calm consumer utility | **Editorial Light Utility** | *Gentler Streak*, *Structured*, *LookUp* | Floating bottom capsule tab bar, detached circular FAB/filter pills | Crisp `#FFFFFF` / warm off-white canvas; zero glass on charts or copy |
| High-stakes live telemetry, travel, logistics, finance | **Operational High-Contrast** | *Flighty*, *Wise* | Map overlays, sheet headers, search pill (higher-opacity glass for finance) | Matte solid cards; tabular numerals; unmistakable semantic status badges |
| Photography, weather, astronomy, ambient time | **Atmospheric Dark Optical** | *Lumy (iOS 27)*, *Moonlitt*, *Return* | Split corner/bottom capsules and HUD pills over live sky/map/video | Deep obsidian/twilight gradient; `1px` specular-rimmed dark cards |
| Dense dashboards & multi-pane pro telemetry | **Spatial Bento & Sidebar** | *Tide Guide*, *Structured (iPad)* | Floating inset left glass sidebar + top location/filter pills | Calm twilight/neutral bento modules with generous inner padding |
| Writing, notes, knowledge, creative canvas | **Canvas-First & Editorial** | *Tot*, *Craft*, *Concepts* | Minimal corner icon clusters, floating pill headers, radial tool wheels | Unobstructed paper/document canvas; serif + sans hierarchy |
| Single-purpose joyful/tactile instrument | **Expressive Anti-Chrome** | *grug*, *(Not Boring) Camera* | Intentionally minimized or custom-crafted when entire world is cohesive | Bespoke tactile surface or flat paper palette with total consistency |

> **Using Mobbin alongside this skill:** The bundled screenshots establish foundational iOS 27 Liquid Glass taste. If the **Mobbin MCP** (`search_screens`, `search_flows`) is connected in your environment, query it for domain-specific flows (e.g., onboarding, paywall, empty states, checkout) while keeping these north-star rules as your quality filter.

## Step 3: Apply the Non-Negotiable Taste Laws

1. **Glass is Chrome, Never Content:** Restrict Liquid Glass to floating navigation bars, tab pills, sidebars, toolbars, detached FABs, and spatial map/media HUDs. Never wrap list rows, editorial articles, flight/financial cards, or form groups in `.glassEffect()`.
2. **Earn Every Pixel of Refraction:** Liquid Glass needs scrolling content, photography, maps, or atmospheric lighting underneath to refract. Placing glass over a flat, motionless monochrome box creates a muddy gray rectangle.
3. **Single-Accent Tint Discipline:** Keep secondary controls monochromatic/neutral glass and reserve **one** accent tint for the primary action (e.g., Gentler Streak's coral active tab, Structured's coral `+` FAB, Apple Maps' blue `Plan` pill). Let user data, charts, or photography carry the rest of the color budget.
4. **Detach High-Priority Actions:** Use floating capsules instead of heavy full-width opaque bars, and detach primary actions (`Tab(role: .prominent)`, `Tab(role: .search)`, or a clean trailing circular pill) so navigation breathes edge-to-edge.
5. **Typography & Whitespace Carry Hierarchy:** Replace heavy card borders and divider clutter with crisp SF Pro / editorial hierarchy, generous spacing, **Title-Style Capitalization** on section headers, and `.monospacedDigit()` on every timestamp, countdown, price, and metric. See [references/typography-color-density.md](./references/typography-color-density.md).
6. **Design for Function First, Delight Second:** Following WWDC's core design principles (*Purpose, Agency, Familiarity, Flexibility, Simplicity, Craft, Delight*), every micro-interaction should clarify spatial state or save a tap—never slow the user down.

## Step 4: Calibrate Visually & Define Your UX Plan Before Coding

Before proposing a layout or writing SwiftUI views for a new feature:

1. Pick the matching row from the archetype table above.
2. Open 1–2 relevant reference images listed in [references/screenshots/INDEX.md](./references/screenshots/INDEX.md) to visually ground spacing, pill sizing, contrast, and layer separation.
3. Explicitly state your **UX & Layer Plan** in 4 lines before writing code:
   - **Primary human answer & flow:** The #1 question answered in < 1s, disclosure tiers, and how actions stay optimistic/reversible.
   - **Content layer:** Surface color/material, typographic hierarchy, density target.
   - **Functional glass layer:** Exact floating controls, variant (`.regular` vs. `.clear`), and scroll-edge strategy.
   - **Color budget:** Single primary accent + semantic status colors only.

## Next Skills in the Suite

- For exact iOS 26 → iOS 27 material rules, dark-mode shifts, and slider behavior, load **`liquid-glass-hig`**.
- For SwiftUI implementation code (and when to bridge UIKit), load **`swiftui-liquid-glass`**.
- For GPU-efficient glass morphing and motion choreography, load **`liquid-glass-animations`**.
- For iPadOS multi-window, sidebar, and menu bar design, load **`ipados-adaptive-layout`**.
- For pre-ship critique and accessibility checks, load **`ios-design-review`**.
