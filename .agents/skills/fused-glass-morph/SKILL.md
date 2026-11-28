---
name: fused-glass-morph
description: Design and debug Commander custom Liquid Glass controls that fuse, peel apart, or expand from a compact trigger into a menu or card, including a trigger that becomes a traveling glass lens. Use for material and container decisions, glass transitions, icons and labels during overlap, input and accessibility, and morph performance. For native titlebar hosting and split-layout motion, use macos-glass-motion.
---

# Fused glass morphs

For Commander's persistent composer guests and hosted sidebar capsules, two glass surfaces stay alive in one `GlassEffectContainer`. Their **frames** move toward or away from each other. The container merges nearby outlines; icons and labels need their own content motion. An effect that genuinely enters or leaves the hierarchy can instead use Apple's glass effect transitions. Choose the path before changing view identity. A system menu owns its presentation; this pattern does not promise the same fusion for that menu.

This is Commander's in-app pattern. The sidebar titlebar accessory is the same idea in a hosted track; read [macos-glass-motion](../macos-glass-motion/SKILL.md) for that geometry follower. Use [swiftui-animation-control](../swiftui-animation-control/SKILL.md) for transaction scope, springs, and completion.

## Read by task

| Task | Read |
| --- | --- |
| Apply Apple's custom-view guidance; choose standard controls, material, modifier order, and APIs | [Apple custom-view companion](references/apple-custom-views.md) |
| Decide when surfaces fuse and how to set spacing, IDs, shapes, and glass | [Fusion rules](references/fusion-rules.md) |
| Choose persistent fusion or insertion/removal, including a trigger-to-menu morph; stage icons and labels | [Morph paths and foreground content](references/morph-and-icons.md) |
| Diagnose a snap, stray glyph, dead click region, contrast issue, or hitch; plan temporal checks | [Morph review and diagnosis](references/morph-review.md) |
| Build a control that becomes a round glass lens and opens a card; stage one morph value; take taps above an iOS safe-area bar; record and step through a morph's frames | [Lens morph](references/lens-morph.md) |
| Change the composer jump-to-latest chip | [Composer jump chip](../../../docs/composer-jump-chip.md) |
| Change the composer plan chip (seed / pill / card) | [Plan chip](../../../docs/task-plan-chip.md) |
| Change the composer context meter (ring / card) | [Context meter](../../../docs/context-meter.md) |
| Change the `/` and `$` command panel | [Command panel](../../../docs/command-panel.md) |
| See what already failed on this SDK | [Failures](../../../docs/investigations/2026-09-composer-glass.md) |

Read the live source before editing. This skill records invariants, not a second copy of the views.

## Persistent-guest workflow

1. **Name the two surfaces.** One is the host (composer box, sidebar toggle). One is the guest (jump chip, creation capsule). Keep both mounted through that guest's active lifecycle; an outer feature may mount or unmount the whole control.
2. **Preserve Commander's persistent effect identities.** Give each guest a stable `glassEffectID` in one `@Namespace`; do not change IDs or mount state to start a persistent peel. Geometry and container spacing drive proximity fusion, while IDs coordinate effect identity for transitions.
3. **Use Commander's shared recipe and stable shape types.** Its mounted guests use matching regular interactive glass with a light tint. Guests that fuse with each other share a shape type; a guest may differ from its host. Keep the same `RoundedRectangle` type when animating its radius. Material experiments are visual hypotheses, not new API guarantees.
4. **Animate frames, not presence, for mounted guests.** Width/height, offset or padding, and a reveal progress value. Keep the glass visible; stage foreground symbols and labels independently.
5. **Decide what may change size.** If the host sits in a `safeAreaBar` or other inset, the guest must **not** grow that inset. Overlay + offset. If the host is an unconstrained accessory, animating the guest's layout frame is fine.
6. **Scope the animation to the guest.** Do not wrap a scroll-driven flag in `withAnimation`. Do not put `.animation(..., value:)` on a `ScrollView` ancestor.
7. **Keep high-frequency state out of the moving tree's `body`.** Pin flags and scroll phase belong in a probe or in action closures. Reading them from the transcript `body` rebuilds the `LazyVStack`.
8. **Hit-test the chip, not the glyph.** A macOS `.plain` image button only accepts clicks on the symbol. The button style must fill the capsule and own the glass.
9. **Reduce Motion snaps both frame and symbol.** Initial mount paints at the destination; a later semantic reveal can animate.

## Staged trigger-to-card morph

When one guest changes size, place and shape in stages, such as a control that becomes a lens and opens a card, follow the context meter's approach in [lens morph](references/lens-morph.md):

1. **One value, one spring per direction.** Each part reads its own window of the interpolated value. Do not sequence a second spring with a delay; a reversal must retarget from what is on screen.
2. **Geometry keeps overshoot; appearance does not.** Outline and position may pass their destination with the spring. Clamp colors, blur, scale and opacity.
3. **Content rides inside the lens.** Lay out the destination at its final size, magnify and blur it from the same value, mask it to outside the host, and build it only while it is visible.
4. **Act on the press for a moving target.** A tap misses when the guest moves farther than the tap tolerates between press and release.
5. **On iOS, UIKit does not hit-test a `safeAreaBar` outside its bounds.** A guest drawn above the bar needs clear proxy targets at the conversation level, and a sheet fallback where the destination does not fit.

## Portable examples

[GlassMorphExamples.swift](examples/GlassMorphExamples.swift) demonstrates a mounted pair with foreground opacity derived from interpolated progress, a real insertion/removal transition, a staged lens that opens a card from one value, and a static union. Adapt the relevant mechanism to the existing control; these standalone fixtures do not replace Commander's production views or establish a runtime visual pass. Read the [companion's example notes](references/apple-custom-views.md#adapt-the-examples) before copying a pattern.

## Commander context

Current implementation, ownership, source maps, and scroll contracts live in the project docs linked above. The sidebar's placement and hosting environment live in [workspace chrome](../../../docs/workspace-chrome.md); appropriate real-window checks live in [verification](../../../docs/verification.md). Use those documents and their production sources instead of keeping a parallel implementation map in this skill.

## Companion skills

- [macos-glass-motion](../macos-glass-motion/SKILL.md): persistent titlebar glass and geometry following
- [swiftui-animation-control](../swiftui-animation-control/SKILL.md): transactions, springs, completion, Reduce Motion
- [swiftui-specialist](../swiftui-specialist/SKILL.md): `@Observable` invalidation and animation APIs

## Maintenance

Update this skill when the reusable glass procedure or API understanding changes. Commander behavior and useful investigation evidence belong in [docs/](../../../docs/maintenance.md). Routine fixes that restore documented behavior need no skill or ledger update.
