# Identity, transitions, content, and geometry

## Match the effect to the kind of change

| Change | Mechanism |
| --- | --- |
| Same view changes size/rotation/opacity | Animatable property interpolation |
| A conditional child enters or leaves | Transition plus animated insertion/removal |
| Text or numeric content changes in place | `contentTransition` plus animated content change |
| Element moves between layouts | Stable identity/layout interpolation; matched geometry if appropriate |
| Data rows are inserted/deleted/reordered | Stable model IDs and the container's supported behavior |

Do not use a transition to fix a property that is not interpolating, or force an `.id` change simply to restart an effect. An identity change can reset state, focus, scroll position, tasks, and hosted controller lifetime.

## Conditional insertion/removal

```swift
// Fragment inside a stable container whose state change is animated.
if showsInspector {
    InspectorContent()
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
}
```

Attach the transition to the child that actually enters/leaves. Keep the parent identity stable. Specify a reduced-motion alternative, such as immediate layout or opacity-only motion.

For a collapsing region, distinguish these designs:

- **Reflow:** its layout height/width shrinks and siblings move; real text may rewrap.
- **Reveal:** content retains its layout size inside a changing clip/reveal region.
- **Visual departure:** an overlay/snapshot animates out while final layout is already committed.

Choose based on the intended effect. Hiding geometry problems with a snapshot gives the app responsibility for live input/accessibility state and snapshot freshness. A measured reveal must handle text-size/content changes without creating a geometry feedback loop.

## Layout modifiers versus visual effects

`frame` participates in layout proposals and reported size. `offset`, rotation, and scale primarily alter rendering relative to the layout slot. Moving a view visually does not necessarily make siblings reserve the new space.

This explains common failures:

- An offset inspector covers detail instead of resizing it.
- A scaled label becomes blurry or overlaps because its layout slot stayed fixed.
- Animating width causes text to rewrap continuously even though the intended effect was a slide.
- A `.fixedSize()` descendant resists compression and changes the parent's minimum budget.

Use a real layout container/constraint for a resizable pane. Use render effects for lightweight emphasis when overlap is intentional. Inspect hit testing and accessibility as well as the drawing.

Modifier order matters. A frame outside a matched/animated effect can impose a different size than a frame inside it. A clip applied at one level may cut a shadow or removal transition while the same clip at another level does not.

## z-order and clipping

During removal, an outgoing child can appear to vanish behind an opaque sibling in a `ZStack`. Inspect drawing order; give overlapping participants stable explicit `zIndex` values when the effect needs them. Do not animate z-index expecting a continuous depth effect—it establishes drawing order.

Use clipping only where the reveal needs it. A `clipped()` ancestor can hide moving content or shadows before the transition completes. Conversely, an unclipped moving child can draw over a toolbar. Define that boundary intentionally.

## Matched geometry

`matchedGeometryEffect(id:in:properties:anchor:isSource:)` links geometry for matching IDs in a shared namespace. Apple specifies:

- insertion and removal in the same transaction can interpolate frames in window space;
- it links geometry, not the complete rendering/content transition;
- exactly one currently inserted source view per group must have `isSource = true`, or results are undefined.

Practical rules:

1. Derive IDs from stable semantic items, not indexes or newly generated UUIDs.
2. Keep the namespace owner stable for the effect's lifetime.
3. Ensure one active source; use `isSource: false` for followers that coexist.
4. Choose `.position`, `.size`, or `.frame` according to which geometry should match.
5. Define fade/content replacement separately if the source and destination render differently.
6. Inspect frame/modifier ordering and clipping if size morphs jump.

Do not assume separate windows, sheets, or navigation presentation contexts share a usable geometry space merely because the namespace value is passed through. Verify the specific container and use supported navigation transitions when the effect is navigation.

`geometryGroup()` can help when child geometry should be isolated from parent geometry propagation, but it is not a fix for every insertion jump. Reproduce the propagation issue first and compare it with a simpler stable hierarchy.

## Numeric/text content

Use a numeric content transition for an actual numeric change where rolling digits communicate progress. Format the number consistently and reserve suitable width where layout jitter is undesirable (for example, monospaced digits for a changing counter).

`contentTransition` defines how content changes; an animation transaction still supplies timing. Replacing an entire text view with a new identity may turn the operation into insertion/removal instead.

For frequent or streaming text, animate high-level state changes rather than each rewrap. Avoid `drawingGroup` as a blanket “make text animation smooth” fix: rasterization changes cost and visual behavior and should be measured.

## Lists and stable identity

Use persistent model IDs for `ForEach`, `List`, and `Table`. Index-based identity when rows can reorder, content-derived IDs when text changes, and `.id(UUID())` destroy the continuity that animation needs.

Keep one predictable row structure per element and perform filtering/sorting outside row builders. Follow Apple's `swiftui-specialist` identity/performance references when changing a large data-driven container.

### Removing rows from a scrolled lazy stack

On iOS 27, a row that leaves a `LazyVStack` in a `ScrollView` inside an animated update stays the stack's realized content until the animation ends, with any transition, `.identity` included. Rows that the removal shifts into the viewport are not realized meanwhile. When the removal shrinks the content under an offset near its end, the scroll view clamps the offset and the viewport shows only the departing rows, then nothing, until the animation finishes. Content that shrinks under a finger is worse: the offset is not clamped while tracking, so nothing is realized until the finger lets go. For a swap like this, fade the leaving rows as state (an animated opacity while they are still rows), make the removal in a transaction with `disablesAnimations`, have the arriving row fade itself in on appearing, and defer the swap while the scroll phase is not idle. The Commander transcript's live-step handoff is the worked case; see [composer and jump chip](../../../../docs/composer-jump-chip.md).

### Commander history disclosure

For stationary content behind a moving cover, keep that content mounted at full size as a sibling of the opaque cover. Put the existing disclosure bar at the cover's moving edge. One `@Animatable` height drives the cover and its children at their current interpolated dimensions. Disable descendant animation inside this generated body so native children do not start a second spring; keep the cover's own interpolation outside that suppression. The Settled implementation is described in [workspace chrome](../../../../docs/workspace-chrome.md#settled-history-cover). Collapsed content also clears its `FocusState` binding, disables interaction, and leaves the accessibility tree.

Failed approach: conditionally inserting the whole list with a move or opacity transition mixes native table replacement with the shelf's upward layout movement. Changing the transition alone does not preserve the table or its scroll position. The populated native-window regression is `SidebarStoreTests.settledShelfKeepsItsNativeListAndScrollPositionThroughReversals`; a text-only disclosure preview does not exercise this behavior.

Geometry failure: a top-aligned reveal sends the rows through the same movement as the header. A separately animated clipping viewport can also reach intermediate sizes without staying synchronized with the bar. A geometry group and intermediate inbox-height checks did not establish that alignment. Measure the actual bar and cover edges frame by frame in both directions, as well as the fixed content anchor. Derive their positions from one interpolated value rather than matching independent curves.

Keyboard failure: clipping, hit-testing suppression, accessibility hiding, and `.disabled` alone did not release the native table's first responder. A down arrow still changed its selection and reopened the collapsed shelf. Bind `.focused` to a shelf-owned `FocusState` and clear it on collapse. The native regression includes an expanded-table arrow positive control before checking that the hidden list ignores the same event.

Sources: [matched geometry](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)), [transitions](https://developer.apple.com/documentation/swiftui/transition), [contentTransition](https://developer.apple.com/documentation/swiftui/view/contenttransition(_:)), [geometryGroup](https://developer.apple.com/documentation/swiftui/view/geometrygroup()).
