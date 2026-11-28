# Trigger-to-card lens morph

Use this reference to build a control inside a host's glass that opens a card by becoming a round glass lens. The lens peels off the host and grows while it travels, carrying the card's content magnified and blurred. It then takes the card's shape. Closing collapses it back into the control. It records how the composer's context meter got this motion on 2026-09-24, over four requests: what was asked, what was built, what failed, and how it was verified. [Context meter](../../../../docs/context-meter.md) and its linked source are authoritative for current behavior and values; numbers here are what shipped that day. [StagedLensCardExample](../examples/GlassMorphExamples.swift) is a standalone version of the technique. It type-checks for macOS and iOS but has not been run.

## The requests

| # | Request | Result |
| --- | --- | --- |
| 1 | The ring already morphed straight into the card. Instead, clicking it should "develop a liquid glass button/drop behind it, move up as a circle inside the drop, get to its location, then expand", with the ring staying the same view. It should look "like a drop of water landing on the page and expanding with the ripple", reverse on close, and feel like Apple's menus on iOS. | A drop that rose, landed, then spread into the card. Superseded; see [version 1](#version-1-a-drop-then-a-spread). |
| 2 | A recording of version 1: "look at it frame by frame, just understand this animation". | Analysis only, no code. The findings are in [version 1](#version-1-a-drop-then-a-spread). |
| 3 | A recording of the iOS Mail "…" menu: "this is sorta the style … match this + any other issues you find". Added mid-turn: "make the color of the smaller circle match the expanded as we go too". | The lens, [version 2](#version-2-one-value-staged-windows). |
| 4 | "can we apply this to ios too?" | The same lens shared with ControllerMobile. See [porting to iOS](#porting-to-ios). |

A written description of a motion is a starting point. Once the user supplies a reference recording, the recording is the specification.

## Version 1: a drop, then a spread

Version 1 ran two animated values, `rise` (slot to a 44-point drop landing where the card's ring would sit) and `spread` (drop to card). The spread started 200 ms after the rise and the fall 160 ms after the gather, sequenced with cancellable delayed work. The drop stretched along its path and squashed if its spring overshot the landing. Stepping through the user's recording of it at about 56 fps showed:

| Observation | Cause |
| --- | --- |
| The drop was visibly airborne for only about 80 ms. | The slot sits in the controls row, 50–60 points below the box's top edge, and the drop landed only about 40 points above it. Most of the rise happened inside the host, where the drop fuses into it. |
| Opening showed a bright white oval sliding up through the host. Closing merged invisibly. | The host's glass is `.interactive()`. The press lit the drop on the way up; nothing lit it on the way down. |
| The spread read as a capsule stretching sideways, not a ripple. | It went straight from a 44 × 44 circle to a card about 300 × 120. The width changed far more than the height. |
| Card text was cut off during both directions. | Rows appeared at 60% of the spread, when the outline was only about 200 of its 300 points wide. |
| The close fell as a rounded square, not a drop. | The fall's delay ran out before the gather had shrunk back to a drop. |
| A bare 14-point ring crept across the prompt for about 0.25 s at the end of the close. | The fall's bouncy spring has a slow tail, and the glass had already merged into the host, leaving the ring alone. |
| A 42 ms gap in the recording as the rise began. | Unresolved: either the recorder or a first-frame hitch. |
| The best moment: the host's edge pulled up into a curved neck and snapped off. | The composer's `GlassEffectContainer` fused the drop and the box while they were close. This part carried into version 2. |

Two stages sequenced by delays make a visible stop between them and need tuning against each other. They fail whenever one stage ends earlier or later than the delay assumed.

## What the reference does

Frame by frame, the Mail "…" menu opens like this:

1. The button brightens and grows slightly under the press, and its glyph fades.
2. Its glass detaches as a small circle, about 44 points, and never stops. It keeps growing as it travels, to about 90 and then 150–200 points. The menu rows appear inside it early, magnified and blurred, with refraction at the rim.
3. The circle flattens into the menu's proportions, its content sharpens, and it settles with a slight overshoot.

Closing collapses the menu into a round lens at once. The content blurs away, the lens narrows into a teardrop neck, and the button absorbs it, in about 0.28 s with no bounce.

The difference from version 1 is continuity. Size, position and shape change in overlapping stretches of one motion, with no stop between them.

## Version 2: one value, staged windows

### One value, one spring per direction

[`ContextUsageMeterState`](../../../../Commander/RemoteUI/ConversationComposerComponents.swift) is a small `@Observable` class with `isExpanded` and `morph`. `setExpanded` sets `isExpanded` outside any animation, then sets `morph` to 1 or 0 inside `withAnimation`. It uses `.spring(duration: 0.5, bounce: 0.16)` to open and `.spring(duration: 0.36, bounce: 0)` to close. Under Reduce Motion, `snap(to:)` sets both in a transaction with `disablesAnimations`. A click mid-motion retargets the one running spring, so a reversal continues from what is on screen with the velocity it already has.

Separate springs per property were considered and rejected. The expectation was that several springs on one leaf would drift apart on reversal and that delayed stages need cancellation logic; that expectation was reasoned, not tested. One value avoids both problems and leaves nothing to cancel. The class exists because iOS draws the lens in one view and takes its taps in another. A single-host control could keep the same two values in `@State`.

### Stages are windows of the value

`ContextUsageLens` in the [Mac implementation](../../../../Commander/RemoteUI/ConversationComposerComponents.macOS.swift) and [iOS implementation](../../../../ControllerMobile/Design/ConversationComposerComponents.iOS.swift) is an `@Animatable` view that receives the interpolated `morph` and computes every part from it in `body`. The staging comes from which stretch of `morph` each part uses:

```swift
/// Reaches 1 at `end` and holds, keeping any overshoot past 1.
func lead(_ p: CGFloat, until end: CGFloat) -> CGFloat { min(max(p, 0) / end, 1) + max(0, p - 1) }
/// Smoothstep below 1, unchanged past it so overshoot still shows.
func ease(_ p: CGFloat) -> CGFloat { p < 1 ? p * p * (3 - 2 * p) : p }

let grown = lead(morph, until: 0.6)
let travelled = ease(lead(morph, until: 0.85))
let formed = max(0, (morph - 0.5) / 0.5)   // unclamped: carries overshoot
let shaped = min(max(formed, 0), 1)
```

| Driver | Parts it moves | Why this window |
| --- | --- | --- |
| `grown`, done at 0.6 | Lens diameter from the slot to the card's shorter side; ring from 14 to 64 points and line from 2 to 7; the ring's category colors (`detail`); the ring button's hit size | The lens is full size before it arrives, as in the reference. The colors are the "match the expanded as we go" request: the small ring splits into the card's colors as it grows, so it arrives already matching the card. |
| `travelled`, done at 0.85, smoothstep | Lens center from the slot to the card's center | The ease makes the lens swell in place before it leaves the row, and on close it reaches the slot quickly instead of creeping. That cut the bare-ring tail from about 90 ms to about 40 ms. |
| `formed`, from 0.5 | Outline from round (`lens × lens`) to the card's width and height | It overlaps the end of the travel, so there is no stop. A card about 300 × 120 can only be round up to its height; after that it takes the card's proportions, which avoids the capsule stretch. |
| `shaped` (`formed` clamped) | Corner radius from `min(size)/2` to 18; ring offset to the card's bottom-leading corner; rows from 1.18× scale and a 12-point blur to sharp; the ring's labels (0.5 to 0.9) | These should not overshoot. |
| `reveal(morph, 0.25, 0.6)` | Row opacity | The rows show early, blurred, like the reference. |

Overshoot policy: `lead` and `ease` pass values past 1 through, so the open spring's bounce shows in the outline and the ring. Colors, blur, scale and opacity use clamped values, so the bounce never tints or re-blurs the card.

On 2026-10-01 an iPhone recording, stepped frame by frame, showed the ring's whole change from the warning tint to the category colors in about four frames at 60 Hz. `grown` ends at 0.6, which the open spring reaches in about 150 ms. The colors now follow `morph` raised to 1.5. In a simulation of the springs, this spreads the open's blend over about 200 ms and cuts its largest step per 60 Hz frame from about 14% to about 8%. The close's blend ends as the lens reaches the box instead of tinting the bare ring there. Reading the ring's code during that review found a second discontinuity in short categories' arcs: each arc got its gap once the growing gap fit twice into it, so its end jumped by the gap. Whether an arc has a gap is now decided once per reading from its length.

The same recording showed the close leaving the bare ring behind. The glass merged into the box with the ring still about 25 points above its slot, and the ring then crept the rest of the way over about eight frames, while the lens bulged out under the box's bottom edge. The critically damped `.spring(duration: 0.36, bounce: 0)` spends about 140 ms on the last 17% of the morph. The close became `.spring(duration: 0.42, bounce: 0.3)`. In a simulation, its first six frames stay within 0.02 of the old close's morph, and the ring lands about 100 ms sooner. Every part of the lens clamps a morph below 0 to its resting pose, so the spring's undershoot never shows.

### Content inside the lens

A mounted guest has no framework content transition, so the lens applies the magnification and blur itself, from the same `morph`. This is one geometry owner, not a manual blur layered on a system transition (see [morph and icons](morph-and-icons.md#compact-trigger-to-menu)). The card is laid out once at its final size and centered on the lens's current center. It is scaled and blurred, and clipped by the lens's `clipShape`. It is also masked to the area above the host's top edge:

```swift
.mask(alignment: .top) { Rectangle().frame(height: max(0, -frame.minY)) }
```

Without the mask, the part of the lens still inside the box showed the rows as smudged text over the prompt. With it, only the ring shows inside the host.

The rows exist only while `rowsOpacity > 0`. The glass modifier and the ring button stay mounted at all times; only this foreground subtree is conditional. See [accessibility](#the-accessibility-tree-still-held-the-hidden-rows) for why.

### Glass and layout

- **Shape:** the lens is the existing `"contextUsage"` guest in the composer's `GlassEffectContainer(spacing: 8)`. One `RoundedRectangle(style: .continuous)` animates its radius from half the size (a circle) to 18, so the shape type never changes. The peel-off neck at the box's edge comes from the container, with no extra code.
- **Layout:** the slot is a fixed clear frame in the controls row, reported with an `anchorPreference`. The lens is an overlay of the box, drawn with `offset`, so the safe-area reservation never changes.
- **Transaction:** the lens ends with `.transaction { $0.animation = nil }`, which predates this work. The leaf computes every frame from `morph`, so no input changed in the same transaction, such as the card frame, hover or the expanded flag, starts an animation of its own inside it. That keeps one owner for the geometry. This is an exception to [animation scope](fusion-rules.md#animation-scope): the trigger is a click, never a scroll or geometry callback, and the animated value belongs to the leaf alone.
- **Ring:** the ring is one `Button` inside the lens from rest to open, offset toward its corner by `shaped`. At rest the button's frame is the whole slot. A `contentShape` larger than a button's frame does not widen its hit area, so the frame itself grows with the ring.

## Input on a moving target

On the Mac, a click on the lens while it returns should reopen the card. A SwiftUI tap on the container missed. The likely reason is movement: the lens moves about 30 points in the 20 ms between a synthetic press and release, so the release no longer lands where the press did. That was inferred from the spring's speed, not measured. A `DragGesture(minimumDistance: 0)` on the container never fired either, and its cause was not found. What worked was acting on the press in AppKit. [`ChipClickAway`](../../../../Commander/Views/TaskPlanView.swift) already runs a local `NSEvent` monitor for click-away and Escape. It gained an optional `onInside` for presses inside its bounds, which are the lens outline, because it is the lens's `.background`. The host arms it while returning and passes `setExpanded(true)`, which is idempotent, rather than a toggle. The monitor returns the event, so the ring button stops hit-testing while returning to avoid handling the press twice.

The rule: when a target can move farther between press and release than a tap tolerates, act on the press and make the action idempotent.

### Controls in the open card

The [effort slider](../../../../docs/effort-slider.md) put a drag control in a lens card on 2026-09-25. On the Mac, SwiftUI tap and drag gestures on views drawn above the composer box never fired from posted events: not inside the lens, not on a clear view beside it in the same overlay, and not after removing the card's scale, blur and mask. Buttons at the same places did fire, and the same gestures fired while the lens still sat inside the box. The cause was not found. What worked was an AppKit `NSView` over the slider that tracks `mouseDown`, `mouseDragged` and `mouseUp` itself, laid out by the host beside a draw-only lens. The host passes the lens's chip rect to `ChipClickAway` as `alsoInside`, so a press on a chip that stays in the row does not also count as a click away. iOS already needs targets outside the bar, so both platforms keep the lens draw-only and move one shared state from their own target.

## A guest with no glass at rest

The [effort chip](../../../../docs/effort-slider.md) is plain text in the row until it opens, so its glass must appear and disappear, unlike the meter's lens. On 2026-09-25 its lens switched `.identity` to `.regular` once `morph` passed 0.01, with its label inside the glass view. A recording, stepped frame by frame on 2026-09-26, showed:

| Observation | Cause |
| --- | --- |
| A white pill appeared around the label on the first frame of the open and vanished on one frame at the end of the close. | The leaf's `.transaction { $0.animation = nil }` makes a variant switch instant. |
| On close, the bare pill sat over the row for about 100 ms before vanishing. | A critically damped close spring spends that long between 12% and 1% of its travel. |
| On the same frame, the label's ink jumped from black to gray. | Foreground inside regular glass draws at full contrast; with identity glass it draws as plain `labelColor`. |
| The slider rose through the card's lower edge, cut in half. | The content was laid out from the growing frame's top edge and revealed from 20% of the morph. |
| The card crept for about 0.3 s after most of the motion. | `.spring(duration: 0.33, bounce: 0.08)` is nearly critically damped; its last 5% takes about 100 ms. |

What fixed it, on macOS 27.2 and the iOS 27.2 simulator:

- **Fade the glass; keep the variant switch invisible.** The surface is a clear view with `.glassEffect` alone in its own `GlassEffectContainer`, and the container's `.opacity` follows a window of `morph` (0.03 to 0.45, smoothstep). The switch to `.identity` happens only at opacity 0. The backdrop material and shadow follow the same value.
- **Put foreground after the container, not inside it.** Plain siblings inside a `GlassEffectContainer` rendered under its glass, blurred. Drawn after the container, the label and card sit above the glass. This gives up the glass's foreground treatment, which is why the ink no longer changes. Check contrast in both appearances and in inactive windows when you do the same.
- **Keep content where it will end up.** Lay the card out at its final frame and let the outline clip it. Fade it in once the moving label has cleared its space (here 0.45 to 0.9), with a small scale and blur.
- **Pick springs from their tails.** `.spring(duration: 0.3, bounce: 0.15)` reaches 1% in about 0.22 s with 0.6% overshoot. `.spring(duration: 0.2, bounce: 0)` closes; the glass is gone before the outline reaches the label, so its slow tail moves only the label.

## Porting to iOS

The original port used **share**: the lens, state, metrics, card placement and slot moved into the already-shared composer components. The current [platform ownership guide](../../../../docs/mobile-design.md) describes the dedicated view implementations; state, common metrics and card placement remain shared. Each lens takes an `accessory: (isReturning) -> View` drawn behind the outline: the Mac passes `ChipClickAway`, iOS passes `EmptyView`. It also takes an `isInteractiveAboveBox` flag. Each platform defines its slot size beside its views: 26 points on iOS for a finger and 22 on the Mac.

### The bar does not hit-test above itself

The iOS composer lives in a `safeAreaBar`, and UIKit does not hit-test the bar outside its bounds. The open card, drawn above the bar, could not be tapped. The lens is still drawn inside the bar's glass container so it fuses and peels as on the Mac, with `isInteractiveAboveBox: false`: only the resting ring takes taps there. The conversation view (`RemoteThreadView`) owns the `ContextUsageMeterState`, passes it to the composer through the environment, and overlays clear proxy targets, `MobileContextUsageTarget`, while the card is open. This is the same pattern as the jump chip's `MobileComposerJumpTarget`. The composer publishes the card's frame and the Compact button's frame in `.global` coordinates through the shared state. The Compact frame is reported by an environment closure, `contextUsageCompactFrameChanged`. The targets are:

| Layer | Behavior |
| --- | --- |
| Full-screen clear layer | Any tap closes, as a menu does |
| Card-shaped clear layer | Swallows taps so the card stays open |
| 80-point circle at the ring | Closes |
| Compact's frame, at least 44 points tall | Closes, then compacts; disabled while busy or disconnected |

The targets are `accessibilityHidden(true)`; VoiceOver reaches the drawn card itself. Focusing the prompt closes the card. The drawn Compact closes the card before compacting, as the target does.

### When the card does not fit

At the largest accessibility text size the card grew past the top of the screen, and nothing could scroll it. The conversation view publishes a `usableTop`: its global `minY` plus its top safe-area inset, which is the bottom of the navigation bar. When the card's window `minY` would fall above that, the ring opens the card in a sheet instead, using `fillsWidth` and medium and large detents. The same large size overlapped the card's ring-row text. A `minHeight` in place of a fixed height fixed that, and normal sizes are unchanged.

### The accessibility tree still held the hidden rows

With `.accessibilityHidden(!isExpanded)` on the invisible rows, XCUITest still found the card's title after it closed. A test that waited for the title to disappear failed, although the card had closed on screen. The fix was to build the rows only while visible. This follows the persistent-guest rule, because the glass and the ring stay mounted; only foreground content is conditional. It also removes the card's layout work while the meter is closed.

## Per-frame cost

An `@Animatable` view runs its whole `body` on the main thread for every frame of its spring. The composer's effort and context lenses and the phone's activity lens each built their card in that body. The card takes closures, which SwiftUI cannot compare, so it never skipped the card: every frame rebuilt and laid out the header, slider, rows and effects. System transitions such as sheets, the zoom, menus and the keyboard are Core Animation animations that the render server runs, so a busy main thread does not drop their frames. SwiftUI's own modifiers animate without running a `body` again. A lens that builds its card each frame drops frames whenever the main thread is busy, for example while a reply streams, and on 2026-09-30 the user reported these morphs as glitchy next to the native ones.

Since then each lens has been a plain view that builds its card once per change and applies an `@Animatable` `ViewModifier` to it. The modifier's body still runs every frame, but it gets the card as `content`, a placeholder SwiftUI does not evaluate again, and only moves, scales, blurs and clips it:

```swift
struct Lens: View {                  // once per change
    var morph: CGFloat
    var body: some View { Card(...).modifier(LensMorph(morph: morph, ...)) }
}

@Animatable
struct LensMorph: ViewModifier {     // every frame
    var morph: CGFloat
    func body(content: Content) -> some View {
        if reveal(morph) > 0 { content.scaleEffect(...).blur(...).offset(...).clipShape(...) }
    }
}
```

`ImageRenderer` renders of the effort and context lenses at twelve points of the morph matched the old implementation pixel for pixel on the iOS 27 simulator. The same rule applies to what sits beside a lens:
- Mount input targets and menus from the non-animated parent, through a small animated modifier that decides when they show.
- Read a value that changes every frame of a gesture, such as the model sheet's presence during a swipe, in the smallest view that needs it, and build that view's closures once in its parent.
- Keep caches the content needs, such as the activity card's sources, above the content that the lens builds and drops.
- Work out values that change once per reading, such as formatted numbers and arc lengths, in the non-animated parent and pass them in.
- Lay text out once at its destination size and scale it with `visualEffect`. A `Text` with `minimumScaleFactor` in a frame that changes on every frame lays itself out again on every frame.
- Keep one color path through a blend. In iOS 27 glass, `tint.mix(with: color, by: 0)` renders differently from `tint`, so returning the plain colors at the ends stepped the ring's color as the spring reached rest or open. macOS `ImageRenderer` showed no difference, so judge colors in a recording of the real surface.

Since 2026-10-01 the Mac context and effort lenses hand their cards to animated modifiers as iOS does. The Mac effort host's input accessory still runs every frame.

An iPhone app's own animations, SwiftUI's included, are capped at 60 Hz unless its Info.plist sets `CADisableMinimumFrameDurationOnPhone`; system transitions and scrolling still run at 120 Hz beside them. ControllerMobile has set the key since 2026-09-30.

### Interactive glass during a streaming reply

On 2026-10-01, simulator captures of the iPhone composer with a reply streaming showed the context lens holding one pose for 30–130 ms at a time during its opens and closes, with the transcript stopped as well. A Time Profiler trace with waiting threads and context switches showed the main thread blocked inside `CA::Context::commit_transaction` during those transitions, on a mutex or on a dispatch queue owned elsewhere, for 15–106 ms at a time and once for 234 ms. Throughout each transition, UIKit's `inProcessAnimationManager` thread ran a display-link callback in the private AnimationKit framework for about a second, waiting each frame on a semaphore with a timeout. The trace did not show which thread held what.

The lens was the one interactive glass taking touches in the composer's glass container; the box is `interactive(false)`, and the effort card's glass does not hit-test. One capture of the same scripted chain for each lens:

| Context lens | Whole-frame holds of 30 ms or more while moving | Longest hold | Main commit waits of 15 ms or more | AnimationKit display-link callbacks |
| --- | --- | --- | --- | --- |
| Interactive glass | 18, 911 ms in all | 100 ms | 14, longest 63 ms | 389 |
| Interactive glass, card blur removed | 12, 606 ms in all | 105 ms | 9, longest 106 ms | 389 |
| `glass.interactive(false)` | 8, 306 ms in all | 50 ms | 4, longest 22 ms | 40, all from the Send button |

A whole-frame hold is a run of frames in which nothing on screen changes, so it misses a held lens while the transcript behind it changes; a ring-only measure of the `interactive(false)` capture still found holds of 32–35 ms in its second and third opens. The iOS lens has used `glass.interactive(false)` since. The holds that remained came during opens while the reply streamed. On the simulator these renderer paths include Metal and IOSurface XPC, and single captures vary, so a device capture is still needed. The Mac lens keeps its pointer press response; the Mac was not profiled in this comparison.

## Verifying the motion

### Motion tests (Mac)

[ContextUsageChipMotionTests](../../../../CommanderTests/ContextUsageChipMotionTests.swift) clicks the real composer's meter in a native window and samples the outline.

- **A round lens in both directions.** `expectLens` requires a sampled frame that is round (width and height within 3 points), at least 50 points wide, and centered above the slot, during both opening and closing.
- **Sampling cadence.** The sampler reads every 20–40 ms. The first reversal checks were flaky: a fast close moves 50–100 points per sample. Logging the gaps between samples showed the harness caused the flakiness, not dropped frames. The jump check therefore measures each step against the whole slot-to-card span, not the shorter reversal distance.
- **Reversal points.** Fixed sleeps were replaced by polling for the moment a reversal needs: `sample(until:)` reads every 4 ms for up to 1 s. The test clicks the returning lens once it is more than 20 points from the card, and interrupts an open once it is more than 60 points from the slot.

The sampler cannot judge per-frame smoothness. Use a recording for that.

### UI tests (iOS)

[ControllerMobileUITests](../../../../ControllerMobileUITests/ControllerMobileUITests.swift) uses the offline fixtures, `CONTROLLER_MOBILE_MOCK_DATA=1` and `CONTROLLER_MOBILE_MOCK_THREAD=queue`; the queued chat carries a Claude breakdown. One test checks that the card opens above the editor, a ring tap closes it, a card tap keeps it open, an outside tap closes it, and the ring is hittable again. Another launches with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and checks that the sheet's title is hittable and sits below the navigation bar.

### Recording and stepping through frames

- **Mac window.**
  - Record from a temporary, uncommitted Swift Testing case. It hosts the composer in an `NSWindow`, then drives it with synthetic mouse and Escape events posted through `NSApp.postEvent`.
  - The case runs `/usr/sbin/screencapture -x -v -V<seconds> -R<x,y,w,h> <file>.mov`. The rect's `y` is flipped against the height of `NSScreen.screens.first`, the main screen.
  - Set `window.level = .floating` and call `orderFrontRegardless()` first. `-R` records whatever is on screen in that rectangle, and without the floating level it once captured another app's window. Delete a capture like that immediately without viewing it further.
- **iOS simulator.**
  - Run `xcrun simctl io <udid> recordVideo --codec h264 --force <file>.mov` in the background while a UI test drives the app, then stop it with `SIGINT`.
  - Pass `-parallel-testing-enabled NO`. Otherwise the test runs on a cloned simulator and the recording shows nothing.
  - Boot the simulator and wait for `xcrun simctl bootstatus <udid> -b` before `simctl ui <udid> appearance dark` or `content_size accessibility-extra-extra-extra-large`.
  - `CONTROLLER_MOBILE_REDUCE_MOTION=1` in a mock-data run turns on only the app's own Reduce Motion paths. It does not turn on the system setting, so motion the system drives, such as the glass's, is not reduced by it. Judge glass motion under Reduce Motion with Settings > Accessibility > Motion > Reduce Motion on.
- **Frames.** Use [video-frame-review](../../video-frame-review/SKILL.md): `probe` maps the recording, `coarse` steps through it, `fine` shows every frame of a transition, and `compare` checks a fix against the baseline. (This review predates ffmpeg on the machine and used a small `AVAssetImageGenerator` tool with zero time tolerances; frame-exact results are the same.)

Step at 0.25 s through the whole recording to find the transitions. Then step at the source frame interval, about 1/60 s, through each opening and closing. This review found things no endpoint screenshot shows:

- The neck at the host's edge.
- The rows smudged over the prompt.
- The bare ring creeping after the glass merged.
- Text cut off by a narrower outline.
- A gap in the recording where the rise began.

Synthetic clicks do not produce the interactive glass's press highlight. Judge the highlight with a real click in the running app.

### Left unverified on 2026-09-24

- VoiceOver activation of the drawn ring and Compact on iOS.
- A real click's press highlight on the Mac.
- A physical iPhone or iPad.
- Reduce Motion on iOS. It runs the same `snap(to:)` path that the Mac tests cover.

## Rules to reuse

- Once the user provides a reference recording, step through it frame by frame and build to what it shows.
- Drive a multi-stage morph from one animated value with one spring per direction. Stage the parts with windows of that value (`lead`, `ease`, offset starts), not with separate springs or delays.
- Let geometry carry overshoot. Clamp colors, blur, scale and opacity.
- Overlap the stages. A pause between "arrive" and "expand" reads as two animations.
- Grow round until the lens reaches the destination's shorter side, then take the destination's proportions.
- Blur and magnify the destination content inside the lens from the same value, and mask it to the area outside the host.
- Keep the glass and the persistent control mounted. Build the content that fades in only while it is visible.
- Close faster than you open, without a visible bounce, and land the glyph with the glass. A critically damped spring creeps through its last stretch; a spring with some bounce reaches rest, and its undershoot stays hidden when every part clamps a morph below 0 to the resting pose.
- For a guest with no glass at rest, fade its glass in its own container from a window of the value, and draw the foreground after that container. Do not switch glass variants on a visible frame.
- When the trigger's label becomes the card's title, carry it rather than fading one out and the other in. On 2026-10-01 the effort chip's label faded under the glass at the chip, the outline rose blank for two frames, and the title appeared at its final place: it read as two animations. Measure each piece at both ends (anchor preferences in the row, the hidden measurement copy in the card), draw a copy styled for each end at its measured size, move both on one interpolated frame, and crossfade them early. Hide the trigger's own label from the same morph value, sharing a short window with the copies, not from the open flag. See the [effort slider](../../../../docs/effort-slider.md#one-raised-glass-layer).
- On a moving target, act on the press, idempotently.
- On iOS, anything drawn outside a `safeAreaBar` needs proxy targets at the conversation level, placed from `.global` frames, and a sheet fallback where the destination does not fit.
- Keep the per-frame body to geometry. Build the destination content once and hand it to an `@Animatable` modifier as its `content`.
- Give a moving glass guest non-interactive glass unless its press response is wanted. On iOS, interactive glass on the context lens kept UIKit's in-process animation running through each transition, and with a reply streaming the main thread's commits waited during it.
- Spread a color blend beyond the lens's early growth, and review it frame by frame. A spring can pass an early window of the morph in a few frames.
- Decide per reading which parts of a drawing exist, such as a gap between arcs. A threshold that compares against an animated value makes a part jump when the value crosses it.
