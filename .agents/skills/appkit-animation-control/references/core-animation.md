# Core Animation: ownership, retargeting, and cleanup

## Know which layer you own

AppKit layer-backed views let AppKit manage their backing layers. Keep view layout and geometry on the view/constraint APIs. Explicit animation recipes are simplest and safest on a dedicated custom sublayer or an intentionally layer-hosting view whose layer hierarchy the app owns.

Before animating a layer, list the properties written by `layout()`, `updateLayer()`, view setters, and your animation code. If two systems write `position`, `bounds`, `opacity`, or `transform`, fix that ownership conflict first.

## Model and presentation

- **Model layer:** target property values your app owns.
- **Presentation layer:** read-only approximate current visual values returned by `presentation()`.
- **Animation:** interpolation applied to presentation; adding an explicit animation does not automatically make the model equal its destination.

The standard explicit-animation sequence:

1. Read the currently presented value, falling back to the model when no presentation is available.
2. Begin a transaction with implicit actions disabled.
3. Write the destination to the model property.
4. Add an explicit animation with `fromValue` from step 1 and `toValue` equal to the model destination.
5. Commit.

Use a stable key such as `"selection.position"` so a replacement targets the animation you own. If an animation already uses the same key, adding the replacement replaces that animation. Capture presentation **before** replacing it.

The model destination remains correct when the animation is removed at completion. Setting `.fillMode = .forwards` and `isRemovedOnCompletion = false` to conceal an unchanged model creates stale state and breaks later updates.

## Retargeting continuity has two levels

- **Position continuity:** start from the current presentation value; no sudden jump.
- **Velocity continuity:** preserve the derivative too; no abrupt change in speed/direction.

A new `CABasicAnimation` with a presentation `fromValue` generally addresses the first, not automatically the second. A `CASpringAnimation` may need an appropriate initial velocity; blindly reusing zero can produce a visible change in momentum.

If the property belongs to an AppKit view and macOS 15+ is supported, `NSAnimationContext.animate` offers documented smooth retargeting with SwiftUI animation semantics. Use that route when it satisfies the requirement instead of manually estimating derivatives.

## Two distinct cancellation policies

### Snap to destination

Keep/write the target model state, then remove only the owned animation key. Presentation resolves to the destination. This is often appropriate for Reduce Motion or teardown.

### Freeze where visible

Capture presentation, write those values to the model with implicit actions disabled, then remove the owned animation. For multi-property motion, capture and commit all relevant values together.

For Auto Layout geometry, “freeze here” also requires reconciling the constraints that own the final geometry. Updating only a layer will be overwritten by the next layout pass. If such a freeze conflicts with the semantic layout, choose a snap or retarget policy instead.

Never mutate the returned presentation object. Never remove every animation on a window/content layer just to stop a custom decorative property.

## Geometry details that create one-frame jumps

- `frame` is derived from `bounds`, `position`, `anchorPoint`, and transforms. With transforms, animate the underlying properties rather than treating frame as independent truth.
- `anchorPoint` changes the pivot and can also move the layer's apparent position. Establish it before motion or compensate position in the same disabled-actions transaction. Compensation must account for the current transform and coordinate spaces.
- Layers and AppKit views can have different flipped-coordinate behavior. Convert coordinates explicitly instead of manually negating y.
- Keep custom-layer `contentsScale` appropriate for the current window backing scale. A layer can look crisp on one display and blurry after moving to another.
- Update `shadowPath` when the shape changes; a fixed path can improve predictable rendering, but stale paths create incorrect moving shadows.
- `masksToBounds` clips shadows and child content. For rounded clipping plus an exterior shadow, separate clipping and shadow ownership into different layers/views.
- `shouldRasterize` is a measured optimization, not an animation quality switch. Scaling a rasterized text subtree can blur; changing its contents every frame can invalidate the cache.

## Completion and lifecycle

`CAAnimationDelegate.animationDidStop(_:finished:)` distinguishes a normally finished animation from one stopped before finishing. Its `finished` value still does not prove the request is current; validate a request revision and layer/view lifetime before applying semantic cleanup.

Adding an animation copies its configuration. Mutating your original animation object later is not a general way to alter the installed animation. Replace the owned animation or adjust an intentionally owned layer clock.

Do not use a completion closure as the only owner of a temporary controller or view. Keep lifetime ownership explicit and invalidate observers/callbacks at teardown.

Sources: [presentation](https://developer.apple.com/documentation/quartzcore/calayer/presentation()), [CABasicAnimation](https://developer.apple.com/documentation/quartzcore/cabasicanimation), [removeAnimation](https://developer.apple.com/documentation/quartzcore/calayer/removeanimation(forkey:)), [Core Animation Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/Introduction/Introduction.html).
