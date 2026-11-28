# Fusion rules

`GlassEffectContainer` batches descendant glass and can merge nearby **similar** effects into one outline. Similarity and proximity are framework-owned. Its `spacing` controls how early nearby shapes blend: a larger value can leave controls fused even at rest if their interior gap is smaller. Choose spacing against the actual resting gap and the intended merge point, then move the frames. [Apple's custom-view guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) describes this behavior.

## Commander fusion contract

| Property | Rule |
| --- | --- |
| Container | One `GlassEffectContainer` around both surfaces. Stable for the control's lifetime. |
| Namespace | One `@Namespace`. Pass it into both `glassEffectID`s. |
| IDs | Keep Commander's effect IDs, such as `"composer"` / `"jumpToLatest"` or `"creation"` / `"sidebar"`, stable. IDs coordinate an effect across hierarchy transitions; they do not set the proximity merge point. Never reassign them to start a persistent morph. |
| Shape type | Guests that fuse **with each other** share a shape type (the sidebar capsules). A guest may differ from its host: the jump chip is a `Capsule` fused into the composer's continuous rounded rect. Matching the host still helps (the plan chip uses the same rounded rect as the box). Do not change a guest's shape *type* mid-morph — that remounts it. Animating `cornerRadius` on one `RoundedRectangle` keeps identity. |
| Glass variant | Same recipe: `.regular.interactive()`, optional light tint. Do not mix `.clear` and `.regular`. A host may turn interaction off with `.interactive(false)` and its interactive guests still fuse and peel: the iOS composer box does, so a tap into its text field does not swell the whole box (checked frame by frame on the iOS 27.1 simulator). |
| Lifetime | During a persistent peel, both glass modifiers stay mounted. Hide the inactive guest with hit-testing and accessibility, not `if`. An outer feature may still mount/unmount the entire control when its data lifecycle starts or ends. Foreground content that exists only partway through a morph, such as a card's rows inside a lens, may be built conditionally from the interpolated progress. With `accessibilityHidden` alone, the context meter's invisible rows stayed in the iOS UI-test tree. The glass modifier and the persistent control stay mounted. |

The [dated composer investigation](../../../../docs/investigations/2026-09-composer-glass.md) records a heavily tinted clear fill that read as a solid disk and did not produce the desired merge with the regular bubble. That is an observed Commander recipe, not Apple's general contract for `.clear`. Read the production glass recipe linked from [the composer guide](../../../../docs/composer-jump-chip.md) for the current tint; use the [Apple companion](apple-custom-views.md#choose-material-and-emphasis) when choosing a variant for a different role.

## Spacing is a material threshold

Layout spacing and container spacing have different jobs. `HStack(spacing:)` reserves layout distance. `GlassEffectContainer(spacing:)` controls when neighboring effect boundaries may blend. Compare the actual nearest edges of the glass-bearing shapes after placement, including offsets and padding. A larger material threshold makes a join begin earlier; it can also erase the desired separation at rest.

For a mounted pair, inspect its fused and peeled endpoints, then the first joining/separating frame. If the peeled gap is intentionally small, choose a container threshold that preserves that separation rather than forcing a wider layout merely to accommodate an arbitrary threshold. For an inserted effect, source proximity also influences the system's matched-glass transition. A large threshold can introduce other nearby effects as possible neighbors, so review the entire cluster. [Apple's container documentation](https://developer.apple.com/documentation/swiftui/glasseffectcontainer).

Do not infer a guaranteed blend curve, neck thickness, or source selection from the spacing value. Those are framework-rendered results. A private shader bridge or a second background capsule is not the first fix for a mismatched merge point.

## What actually interpolates

The container follows **laid-out frames**, not a grouping ID. Animate:

- `frame(width:height:)` of the guest
- padding / offset that moves the guest relative to the host
- the host's width when the sidebar creation capsule contracts

Use `glassEffectUnion` when similar effects should contribute to **one shape at rest**, even across dynamic views or separate layout groups. It does not animate a moving join by changing the union ID; doing so snapped the material on this SDK. [Apple's union documentation](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) specifies matching shape and glass effect for contributors.

Use distinct effect IDs for distinct effects. A shared **union ID** expresses grouping; an **effect ID** expresses effect identity. Neither replaces the stable semantic ID of a model row or the lifetime of its view. Reordering a dynamic collection should retain the element's semantic identity, not generate IDs from its temporary array index. Apple's small indexed union demonstration is not a universal identity pattern for an editable collection.

`offset` moves the drawn view (and usually its glass) without changing the parent's reported size. Use it when the parent is a `safeAreaBar` or other inset. The sidebar creation capsule also uses `offset` so the accessory track can stay a fixed width.

Padding on the host **does** change the parent's size. That is correct for an unconstrained accessory. It is wrong for a composer inside `safeAreaBar(edge: .bottom)` — the transcript inset will animate and fight scrolling.

Document three bounds separately when an overlay moves outside its host: the parent's layout reservation, the material's drawn region, and the action's hit region. A fixed reservation prevents transcript motion but does not prove that an ancestor permits drawing or clicks outside its bounds. Check clipping and pointer routing at the real host/window boundary. The native titlebar follower has a separate coordinate-space contract; read [macOS glass motion](../../macos-glass-motion/SKILL.md) instead of copying an in-content offset into it.

## Foreground is a second track

The glass joins its outline, not the images or labels carried by each control. Keep foreground content inside the view receiving `glassEffect`, and stage its visibility separately from the material. Read [morph paths and foreground content](morph-and-icons.md) before changing icon timing or adding a second icon to a fused lane. Commander's jump chip currently reveals its symbol after the peel begins and hides it promptly on fusion; those durations are product choices, not Apple timing requirements.

## Hit testing

Interactive glass is visual feedback. The control is the `Button`.

On macOS, `.buttonStyle(.plain)` plus an `Image` hit-tests the glyph. Put the glass on a `ButtonStyle` whose body is:

```text
label
  → frame(maxWidth: .infinity, maxHeight: .infinity)
  → Color.clear background
  → contentShape(Capsule())
  → glassEffect + glassEffectID
```

The outer view still sets the diameter. Clicks anywhere on the capsule must fire.

A guest that moves while pressed can escape a tap. The context meter's returning lens ignored clicks, most likely because it had moved on by the release. Act on the press instead, with an idempotent action; on the Mac an `NSEvent` local monitor sees it. See [lens morph](lens-morph.md#input-on-a-moving-target).

On iOS, UIKit does not hit-test a `safeAreaBar` outside its bounds. Keep the drawn guest in the bar's glass container so it still fuses. Take its taps with clear targets laid over the conversation, placed from `.global` frames the composer publishes. The jump chip and the context meter both do this.

If a mounted guest contains an AppKit representable, forward its inactive state to the native view too. An opacity or hit-testing wrapper does not hide a native accessibility subtree or release its first responder. Set native accessibility visibility, prevent inactive text views from accepting focus, and release existing focus when hiding. Check the running hierarchy as well as the image; invisible native controls can otherwise remain exposed.

## Animation scope

Set destination state **without** `withAnimation` when the trigger is a scroll or geometry callback. Attach `.animation(spring, value: isExpanded)` to the **guest** only.

`withAnimation` at the dock/onChange site puts the spring on the current transaction. A `ScrollView` in that update will interpolate content offset. That is the hitch.

A morph triggered by a click is different. The action can set one progress value inside `withAnimation`, provided that value belongs to one `@Animatable` leaf that computes all its geometry from it. The context meter's leaf also ends with `.transaction { $0.animation = nil }`, so no other input that changes in the same update starts its own animation inside the leaf. See [lens morph](lens-morph.md#version-2-one-value-staged-windows).

## Observation

`@Observable` pin/phase objects are for coarsened flags, not per-pixel geometry.

| Allowed | Forbidden |
| --- | --- |
| `onScrollGeometryChange` **action** writes `isPinnedToBottom` | Reading `followsLatest` / `isScrolling` from `TranscriptView.body` |
| `onScrollPhaseChange` **action** writes `isScrolling` | `defaultScrollAnchor(.bottom, for: .sizeChanges)` bound to pin |
| A zero-size probe observes pin/phase and calls `applyReveal` | Animating the composer from the transcript body |

Use coarsened semantic flags in the moving leaf, not per-pixel scroll observations in a large view body. Keep scroll-follow decisions in action/probe ownership rather than coupling them to animation rendering. Commander's current follow latch and jump behavior belong in [the composer guide](../../../../docs/composer-jump-chip.md); a glass styling change must preserve that contract.
