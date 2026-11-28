# Reviewing and debugging a glass morph

Use this reference for an implementation review or a concrete visual/input failure. Begin with the chosen [morph path](morph-and-icons.md); a mounted guest, hierarchy transition, and static union have different failure modes. Match verification to [Commander verification](../../../../docs/verification.md). A skill-only documentation change needs documentation/API checks, not an app launch.

## Establish what owns the effect

Record the trigger and state owner, stable control/effect identities, container/namespace, geometry driver, foreground driver, containing layout reservation, and inactive input/focus behavior. For a source-to-menu transition, identify whether both surfaces are in the same container or whether the system owns a separate presentation. Capture the real resting gap and shape bounds; layout spacing alone can be misleading after offset, padding, or overlays.

If a native split view supplies the geometry, use its current measured position as the follower's input. Do not tune a second spring until it looks close to the split animation. That introduces two owners for the same motion. Read [macOS glass motion](../../macos-glass-motion/SKILL.md) for native followers and coordinate spaces.

## Diagnose the visible symptom

| Symptom | Check first | Useful correction or next evidence |
| --- | --- | --- |
| Controls join while supposedly separate at rest | Actual edge gap versus container spacing; union membership | Tune spacing against the intended gap or remove unintended union membership. Preserve layout spacing if it is the product's density choice. |
| Shapes never join | Shared container, recipe, effect bounds, effective gap, outer clipping | Build a small same-recipe experiment. Move effects into range before changing identity or inventing a background bridge. |
| Outline snaps on reversal or pose change | `if` branches, `.id`, namespace recreation, shape type changes, changing union IDs | Restore the persistent representation for a mounted guest or use an intentional insertion path. Compare the identities before/after. |
| An inserted effect fades without the desired source stretch | Distance from source, selected transition, shared container, animated transaction | Use matching only when source geometry is actually available within range. Materialize may be the correct distant transition. |
| Neck or panel is chopped off | Foreground versus ancestor clipping; host drawing bounds; window edge | Preserve drawing room for the material. Clip the overflowing text without clipping the whole joining surface. |
| Glass looks right but icons overlap, disappear too late, or flash | Two symbol owners, content replacement versus visibility, target/progress confusion, stale delayed work | Use the foreground plan in [morph and icons](morph-and-icons.md), then reverse during the faulty phase. |
| A click works only on the glyph | Button label/style bounds and `contentShape` | Put the hit shape and full-size label inside the button style. Click near several corners of the visible surface. |
| The wrong action fires in a unified outline | Overlapping enabled regions, draw order, transparent hit blockers | Resolve the action regions or activation policy. Fusion and `zIndex` do not define semantic arbitration. |
| An invisible panel still accepts input or VoiceOver focus | Wrapper state, native representable subtree, current first responder | Update native accessibility/focus as well as SwiftUI hit testing. Return focus to the appropriate visible control. |
| Transcript, siblings, or window size move unexpectedly | Animated inset/layout reservation and broad transactions | Use a fixed reservation/overlay for the guest and move animation scope into the leaf. Inspect the layout owner separately. |
| Foreground is poor over scrolling content | Material role, foreground inside effect, fixed color, tint/scrim | Compare default semantic foreground and the intended regular recipe. Check native content placement when AppKit owns the glass. |
| Animation hitches with many controls or during streaming | Effect/container count, invalidated view bodies, frame work | Profile the actual trigger. Distinguish material/render cost from repeated model/view updates. |
| A custom morph looks less smooth on iPhone than the system's sheets and menus | The Info.plist's `CADisableMinimumFrameDurationOnPhone`; an `@Animatable` body that builds content every frame | Without the key the app's animations stop at 60 Hz. Keep the per-frame body to geometry; see [per-frame cost](lens-morph.md#per-frame-cost). |
| A staged morph stops between stages, or stages drift apart on reversal | Separate springs or delay-sequenced stages | Drive every stage from one value with one spring per direction, and overlap the windows. See [lens morph](lens-morph.md#version-2-one-value-staged-windows). |
| An expanding outline reads as a capsule stretching sideways | Width grows toward a wide destination before the height does | Stay round until the lens reaches the destination's shorter side, then take its proportions. |
| Destination text smudges over the host while the lens leaves it | Content not limited to outside the host | Mask the content to the area beyond the host's edge; only the persistent glyph shows inside. |
| A bare glyph creeps after the glass merges on close | The glass merges before the glyph arrives, and a bouncy or linear return leaves a slow tail | Close without a bounce and ease the travel so it finishes early. |
| A press on a moving guest does nothing | The guest moves between press and release | Act on the press with an idempotent action. |
| Taps on a guest above an iOS composer do nothing | `safeAreaBar` hit testing stops at the bar | Use proxy targets at the conversation level placed from `.global` frames. |
| Hidden content is still found by UI tests or VoiceOver | `accessibilityHidden` on content that is not on screen | Build the foreground only while visible; keep the glass mounted. |

Apple owns proximity matching and system transition appearance. The corrections above are diagnostic hypotheses; the [custom-view API guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) and the [dated Commander failures](../../../../docs/investigations/2026-09-composer-glass.md) help distinguish supported behavior from previously observed limitations.

## Inspect time and behavior together

For a motion change, inspect both directions using temporal frames or a recording and live interaction:

| Sample | What to inspect |
| --- | --- |
| Fused rest | Intended single outline, hidden seed content, correct action labels and inactive guest semantics. |
| First separation | Joining neck stays visible; source action remains recognizable; no stray glyph is exposed. |
| Midpoint / first readable content | Foreground fits its own shape; text is clipped appropriately; enabled hit regions agree with visible actions. |
| Peeled rest | Intended gap and shape, sharp foreground, full-surface click response, correct keyboard/VoiceOver order. |
| First contraction | Outgoing text/glyph leaves before it collides; removed actions cannot consume input. |
| Reversal during overlap or fade | Newest intent wins without an identity reset, stale reveal, jump, duplicate symbol, or incorrect focus handoff. |

Do not estimate halfway by reading an animated `@State` target: it normally changes to the destination immediately. Use a recording, supported rendered-geometry observation, or an explicitly owned presentation/progress surface. For app-owned `Animatable` rendering, interpolate and compute locally; do not publish progress back into model state every frame. The animation skill's [springs and interaction reference](../../swiftui-animation-control/references/springs-and-interaction.md) explains that distinction.

[Lens morph](lens-morph.md#verifying-the-motion) has working recipes: recording a Mac test window with `screencapture`, recording the simulator with `simctl io recordVideo` while a UI test drives it, and extracting exact frames with AVFoundation. It also covers the limits of a motion test's outline sampler. Synthetic clicks do not produce the interactive glass's press highlight.

Sample around a state change and the overlap region, rather than collecting only evenly spaced endpoints. There is no universal frame count or timing constant. Record the trigger, direction, observation, and the particular phase that failed. A sequence of still frames cannot establish click routing; click checks cannot establish uninterrupted glyph motion.

## Cover the conditions that can change the result

Select conditions relevant to the surface:

- Toggle repeatedly before settling, then reverse during the glyph fade and during the joining neck. Keep the trigger available; a secondary action can have a deliberate activation policy.
- Change unrelated text/status while the leaf moves. Resize the window, scroll the backdrop, and exercise narrow/wide layout near pane boundaries when those affect its geometry.
- Exercise other glass guests in the same lane together. Review resting and moving action regions, including a jump chip, plan chip, and command panel where applicable.
- Hide the owner or switch thread while a staged reveal is pending. No old completion should revive a guest in the new context.
- Check light and dark appearance, a quiet and visually busy backdrop, inactive-window appearance, increased contrast, and Reduce Transparency.
- Enable Reduce Motion before triggering and, for an owned ongoing animation, while moving. The semantic destination stays usable and no delayed normal-motion stage should survive the change.
- Check keyboard activation, menu dismissal, focus return, VoiceOver labels/order, and clicks across each complete visible control surface. A custom menu also needs its actual menu interaction rules; a plausible animation cannot supply them.

The [Apple adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) explains system appearance/accessibility adaptation; [HIG motion](https://developer.apple.com/design/human-interface-guidelines/motion) explains responsive, understandable feedback. The matrix is Commander review practice, not a claim that every small styling edit requires every interaction above.

## Investigate hitches with a comparison

Use the same trigger, window size, data, and onscreen effect set when comparing revisions. Record whether a hitch is at hierarchy creation, per-frame movement, content updates, or backdrop scrolling. Inspect SwiftUI invalidation and the render path with [Instruments profiling](../../instruments-profiling/SKILL.md) and [project profiling guidance](../../../../docs/performance-profiling.md).

Useful isolated comparisons are a stable small dataset versus streaming, one related effect cluster versus the populated window, and the foreground content temporarily simplified while retaining material/geometry. Make these reversible diagnostic changes. Do not ship a guessed global duration reduction or replace system glass with opaque fill merely because one frame was slow. Apple points to [SwiftUI Instruments](https://developer.apple.com/videos/play/wwdc2025/306/) and [animation hitches/render loop](https://developer.apple.com/videos/play/tech-talks/10855/) from its custom-view performance section.

## Report evidence with its limits

State which mechanism was changed, why it addresses the trigger, which compilation and runtime checks ran, which temporal/input/accessibility observations passed, and what remains unverified. Keep endpoint appearance, continuity, identity retention, click routing, and performance as distinct claims. A build is API evidence; a static preview is appearance evidence; a temporal recording is motion evidence for the sequences actually exercised. Do not describe this reference's example or a previous investigation as a current app pass.
