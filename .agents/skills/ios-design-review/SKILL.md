---
name: ios-design-review
description: >-
  Audits iOS 27 and iPadOS 27 SwiftUI/UIKit code, Xcode Previews, and screenshots for user experience quality, Liquid Glass taste, legibility, iOS 27 compliance, 120Hz animation performance, and accessibility.
  Use before shipping a screen, during PR review, or when diagnosing why an iOS/iPadOS UI feels confusing, sluggish, cluttered, muddy, unreadable, or drops frames.
---

# iOS 27 & iPadOS Design, UX & Performance Review

Run this structured critique workflow on any SwiftUI/UIKit screen, PR diff, Xcode Preview, or screenshot before shipping. Deliver findings ranked by severity—never vague praise.

## Review Workflow

### Step 1: Run the User Experience & Flow Gate
Before inspecting pixels, evaluate whether the engineering actually delivers a great human experience:
- **Anticipatory clarity:** Does the screen answer the user's #1 question in < 1 second using synthesized domain state rather than raw backend fields?
- **Spatial continuity:** Do secondary views use detented half-sheets (`.presentationDetents` + `.presentationBackgroundInteraction`), `.inspector(isPresented:)`, or direct manipulation instead of jarring full-screen teleports?
- **Perceived speed & forgiveness:** Are routine mutations optimistic (frame-1 feedback, zero blocking spinners), and do reversible deletes/archives use a transient `.materialize` Undo pill instead of nagging `"Are you sure?"` dialogs?
- **Non-ideal states & agency:** Are empty (`ContentUnavailableView`), offline/stale, and plain-English error recovery states handled? Are permissions requested only in-context (never ambushing cold launch)?
- **Clear microcopy:** Do buttons use concrete action verbs (`Archive Flight`, `Save Preset`) instead of vague `OK` / `Submit` labels?

### Step 2: Audit Against the 10 Laws of Tasteful Liquid Glass
Evaluate the screen and code using [references/10-laws-rubric.md](./references/10-laws-rubric.md). Immediately flag any **Blocker**:
- Liquid Glass applied to content cards, list rows, or reading surfaces (Functional Layer violation).
- `.glassEffect()` sitting on a flat, static monochrome backdrop with nothing to refract.
- Multiple brightly tinted buttons in the same toolbar pill (Single-Accent violation).
- `.clear` glass over bright media without a 35% dark dimming scrim.
- Colorful cards/photos scrolling behind an iOS 27 bottom tab bar without `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
- Legacy opaque bar overrides (`UINavigationBarAppearance` / `.toolbarBackground` solid fills) clashing with mandatory iOS 27 Liquid Glass.
- Hardcoded `userInterfaceIdiom` branching that breaks continuous iPadOS resizing or resizable iPhone windows.

### Step 3: Run the 120Hz GPU & Animation Hygiene Check
Scan SwiftUI and UIKit code for frame-killers:
- Adjacent custom `.glassEffect()` views missing a local `GlassEffectContainer` (unbatched GPU passes).
- Conditional `if isActive { .glassEffect() }` branches instead of `.glassEffect(isActive ? .regular : .identity)`.
- `.rotationEffect()` animated directly on a `.glassEffect()` view instead of rotating only its inner glyph.
- `.repeatForever()` animations attached to glass surfaces.
- High-frequency timers or scroll offsets read in the same view body that renders `GlassEffectContainer`.
- `Image` + `.onTapGesture` faking a button instead of a semantic `Button` with `.glass` / `.interactive()`.
- Missing `@Environment(\.accessibilityReduceMotion)` gating on morph transitions.

### Step 4: Execute the iOS 27 Verification Matrix
Verify visual and accessibility resilience across every state in [references/verification-matrix.md](./references/verification-matrix.md):
1. **iOS 27 Transparency Slider:** Most Clear AND Most Tinted extremes.
2. **Appearance Modes:** Light Mode (crisp iOS 27 borders on white, no redundant drop shadows) AND Dark Mode (lighter dark glass, inverted darker active tab pill, readable custom dark sheet contrast, no hardcoded white double-strokes).
3. **Accessibility:** Reduce Transparency, Increase Contrast, Reduce Motion, Dynamic Type (`AX3` reflow without clipping), and VoiceOver (icon-only glass pills labeled; decorative reflections marked `.accessibilityHidden(true)`).
4. **Form Factors:** Narrow compact iPhone, iPhone Landscape sidebar, medium/wide continuous iPadOS window sizes, and inactive multi-window focus (`appearsActive == false`).
5. **Physical Device Profiling:** Instruments **SwiftUI** + **Core Animation Hitch Rate** + Xcode **Flash Updated Regions**.

## Required Critique Output Format

Structure every design review response cleanly into five buckets with concrete file/line fixes:

```markdown
## Design & UX Review Summary
**Archetype & Job Fit:** [Name matched archetype & whether the layout + flow match the app's real job]

### Blockers (Must Fix Before Ship)
- **[UX / Law / Rule]:** Exact issue + concrete SwiftUI/UIKit code fix.

### User Experience & Flow
- Glanceability, disclosure tiers, optimistic state / Undo ergonomics, microcopy, and empty/offline/error handling.

### Visual Craft & Polish
- Typography (`.monospacedDigit()`, Title-Case headers), spacing, concentricity, tint restraint improvements.

### Performance & Motion (120Hz)
- Container batching, `.identity` state toggles, state isolation, or UIKit bridge recommendations.

### Verification Gaps
- Any untested states from the iOS 27 Slider / Dark Mode / Accessibility / iPadOS matrix.
```
