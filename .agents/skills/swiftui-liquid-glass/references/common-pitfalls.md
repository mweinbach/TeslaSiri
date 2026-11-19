# Common SwiftUI Liquid Glass Pitfalls & Fixes

Check this list before opening a PR or debugging visual glitches on iOS 26 / iOS 27.

---

## 1. Glass on a Flat Solid Background Looks Muddy
- **Symptom:** A `.glassEffect()` badge sits over a solid `#F5F5F7` or `#111111` background with zero scrolling content or light variation underneath, turning into a dull gray pill.
- **Fix:** Liquid Glass requires visual content or atmospheric light underneath to refract. Either move the control over scrolling/rich content (map, media, feed) or use a clean solid/matte semantic surface instead of glass.

## 2. Colorful Cards Clashing Behind iOS 27 Bottom Tab Bar
- **Symptom:** On iOS 27, vivid cards or photography scroll right behind the floating tab pill with zero soft blur buffer, hurting icon/label contrast.
- **Fix:** Explicitly add `.scrollEdgeEffectStyle(.soft, for: .bottom)` on the scrollable view inside the `Tab`.

## 3. Empty "Ghost" Glass Capsule in a Toolbar
- **Symptom:** Conditionally hiding a button's inner view (`if showEdit { Image(...) }`) leaves an empty circular glass bubble sitting in the navigation bar.
- **Fix:** Conditionally wrap the entire `ToolbarItem` (or use toolbar visibility modifiers on the item itself), never only the label inside `ToolbarItem`.

## 4. Circular Profile Photo Trapped Inside an Unwanted Glass Pill
- **Symptom:** Adding an avatar image to `.toolbar` wraps it in a thick glass bezel with awkward margins.
- **Fix:** Attach `.sharedBackgroundVisibility(.hidden)` directly to that `ToolbarItem` content so the avatar renders standalone alongside adjacent glass pills.

## 5. Mixing Text and Icons Inside One Toolbar Glass Pill
- **Symptom:** `"Edit"` text button and a magnifying-glass icon button merge into a lopsided pill with uneven visual weight.
- **Fix:** Insert `ToolbarSpacer(.fixed)` between text-labeled actions and icon-only clusters so they render as separate, balanced capsules.

## 6. `.rotationEffect()` Distorting Glass Shape Bounds
- **Symptom:** Rotating a view that has `.glassEffect()` causes the capsule/circle silhouette to warp awkwardly mid-animation as SwiftUI recomputes bounding boxes.
- **Fix:** Rotate only the **inner glyph/icon** inside the glass button, or apply container-level transforms outside the glass bounds—never animate `.rotationEffect()` directly on the glass layer itself.

## 7. Using `.onTapGesture` Instead of `Button` on Glass Controls
- **Symptom:** Tap highlight, touch lensing, VoiceOver traits, and pointer hover feedback feel dead or out of sync.
- **Fix:** Always use a real `Button` (with `.buttonStyle(.glass)` / `.glassProminent` or `.glassEffect(.regular.interactive())`), never `Image(...).glassEffect().onTapGesture { ... }`.

## 8. Hardcoded Light-Mode White Strokes Breaking iOS 27 Dark Mode
- **Symptom:** `.overlay(Capsule().stroke(.white.opacity(0.25)))` looks fine in iOS 26 dark mode but creates harsh double borders against iOS 27's lighter dark-mode glass.
- **Fix:** Delete manual border overlays on `.glassEffect()` views—iOS 27 draws adaptive perimeter borders and specular highlights natively.

## 9. Mutating `@State` Inside Custom `init` (iOS 27 Macro Regression)
- **Symptom:** Compiler errors or unexpected state glitches after upgrading to Xcode 27 because `@State` is now synthesized as a macro.
- **Fix:** Initialize `@State` inline at declaration (`@State private var model = FeedModel()`) or update it in `.task` / `.onAppear`, never mutating `_myState` inside `init` before `self` is ready.

## 10. Custom Opaque Bar Backgrounds Blocking Liquid Glass
- **Symptom:** Navigation bars or tab bars show awkward double boxes or lose scroll edge transitions after building with Xcode 27.
- **Fix:** Remove legacy `UINavigationBar.appearance().standardAppearance` solid fills and `.toolbarBackground(Color..., for: .navigationBar)` hacks.
