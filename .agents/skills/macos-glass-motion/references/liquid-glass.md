# Native Liquid Glass controls

## APIs and availability

Checked again against the selected Xcode 27 AppKit `NSGlassEffectView.h` declaration on 2026-09-16. Verify the header in the selected SDK when deployment support or API usage changes:

| API | Minimum macOS | Purpose |
| --- | --- | --- |
| `NSGlassEffectView` | 26.0 | Embed a content view in a dynamic glass material |
| `.style = .regular` / `.clear` | 26.0 | Select the glass style |
| `contentView`, `cornerRadius`, `tintColor` | 26.0 | Content relationship, shape, optional tint |
| `NSGlassEffectContainerView` | 26.0 | Batch similar descendant glass and merge nearby effects |
| `NSButton.BezelStyle.glass` | 26.0 | Standard button glass without a custom wrapper |
| `effectIsInteractive` | **27.0** | Add system interaction feedback to glass; defaults to false |

Commander currently targets macOS 27, so it can set `effectIsInteractive` directly. In a reusable macOS 26 component, gate that property with `if #available(macOS 27.0, *)`. The material itself does not require 27. For older deployments, define an appropriate standard-control fallback instead of silently treating blur as equivalent Liquid Glass.

The [glass view](https://developer.apple.com/documentation/appkit/nsglasseffectview) and [interaction property](https://developer.apple.com/documentation/appkit/nsglasseffectview/effectisinteractive) document the behavior; the installed header establishes the availability annotations, including the macOS 27-only interaction property. A page's publication date is not an availability check.

## Correct hierarchy

```text
App-owned track / layout container
└── NSGlassEffectView (positioned as one visual assembly)
    └── contentView: NSButton
```

Construct and update these AppKit views on the main actor. Set `glass.contentView = button` or to a view that contains the control and its foreground. Apple's [content-view contract](https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview) guarantees that content is placed inside the glass; it does **not** guarantee the same z-order behavior for arbitrary subviews added directly to `NSGlassEffectView`. Keep the glass as the control's background rather than putting an opaque custom fill or another visual-effect view over it.

For a native button inside an app-owned glass view:

```swift
button.bezelStyle = .circular
button.isBordered = false
button.imagePosition = .imageOnly
button.setButtonType(.momentaryPushIn)

glass.style = .regular
glass.cornerRadius = 18
glass.effectIsInteractive = true // This app targets macOS 27.
glass.contentView = button
```

The complete reusable construction is in [GlassButtonExample.swift](../examples/GlassButtonExample.swift).

## Foreground symbols, appearance, and vibrancy

Placing a button in `contentView` solves placement; it is not a promise that every custom subview becomes vibrant. Apple's `NSGlassEffectView` contract says where the content goes. Apple's [vibrancy guidance for `NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview) is separate: standard AppKit controls choose vibrancy where appropriate, while custom drawing in a vibrancy hierarchy may opt in at a **leaf** view through `allowsVibrancy`. Do not override vibrancy on a standard `NSButton` or on the entire glass/hosting assembly. A parent opt-in can make descendants that were not designed for vibrancy look wrong.

Use the control's normal appearance-aware foreground or system label colors for custom monochrome content, and inspect contrast over the actual backdrop. A fixed symbol tint can be a deliberate product choice, but verify it in light/dark and active/inactive windows rather than assuming the material will correct it: Commander's hard-coded black toggle glyph measured near-zero contrast on dark-mode glass and moved to `labelColor`, which matches the approved light appearance and adapts. If a symbol is unexpectedly flat or detached, first confirm it lives in `contentView`, that the control and glass move together, and that the window is active. Do not add a fake blur or force an `NSVisualEffectView` merely to change the glyph.

## Move the material and content together

The initial control was a circular bordered `NSButton`, which appeared as a solid gray disk. After adding a glass wrapper, the geometry owner was changed from:

```swift
track.button.setFrameOrigin(position)
```

to:

```swift
track.glass.setFrameOrigin(position)
```

The borderless button retains the symbol, target/action, focus, and accessibility semantics; the wrapper provides the material. Moving just the button would let the glyph separate from the glass, producing two independently moving visual components.

Do not replace the material on collapse/expand, toggle its presence in an `if`, or use an identity reset to restart its appearance. Stable identity must cover the interactive control **and** its glass assembly.

## Geometry and sizing

- Choose outer size, shape, and symbol metrics for the product's layout. The [Commander guide](../../../../docs/workspace-chrome.md) links to its current metrics.
- Use the accessory track's measured height and center the control in its current bounds rather than copying a prior titlebar height.
- The track/glass frame is app-owned and unconstrained. A component laid out by Auto Layout should change constraints instead of also writing its frame.
- `contentView` can acquire AppKit-managed layout. Do not assert that the inner button's frame must equal the material's frame; [the historical investigation](../../../../docs/investigations/2026-09-sidebar-glass.md) records one such observation.
- Use coordinate conversion when checking hit areas and endpoints. A local `button.frame.origin` does not tell you its location in the window.
- Avoid masking or clipping the glass wrapper's backing layer just to make it circular. Use its public shape property so material rendering, highlights, and shadows remain framework-owned.

For diagnostics of this AppKit pattern, sample both the outer glass frame and inner button's converted bounds. For a hosted SwiftUI container, inspect the moved host and the rendered material separately. Read [Commander workspace chrome](../../../../docs/workspace-chrome.md) for its current integration.

## Interactive behavior and accessibility

`effectIsInteractive = true` is [documented](https://developer.apple.com/documentation/appkit/nsglasseffectview/effectisinteractive) for glass behind or containing interactive controls. It enables system visual feedback; it does not create a button action, keyboard handling, focus semantics, or an accessibility label by itself. The default is `false` on macOS 27; macOS 26 does not expose the property, so do not promise the same glass feedback there even when the embedded button works.

Retain a real control inside the effect:

- localized “Show Sidebar” / “Hide Sidebar” accessible labels;
- stable accessibility identifier `workspace.sidebarToggle`;
- native `NSButton` target/action;
- the existing scene command for `⌃⌘S`;
- a tooltip that describes the action and shortcut.

Do not replace this with an image plus mouse handlers just to obtain the material. Preserve the button's native keyboard/focus behavior. In a real window, click the center **and edge** of the intended glass target, check that the correct action changed state, use the keyboard/scene shortcut, and inspect first responder and accessibility after hiding or reversing the control. A direct target/action invocation proves routing but not physical hit testing or focus. If a custom press animation is added later, determine which property it owns; it must not fight the glass's interactive deformation or the track's translation. See [runtime verification](runtime-verification.md) for the evidence levels.

## Style, background, and multiple effects

Start with `.regular` for the current toolbar-like control. `.clear` exists, but was not used or visually evaluated for this implementation. Tint is optional and is not a requirement for Liquid Glass. Prefer a standard `NSButton` with its macOS 26+ [`.glass` bezel style](https://developer.apple.com/documentation/appkit/nsbutton/bezelstyle-swift.enum/glass) when that satisfies the design; use a custom glass view when the app must own a distinct shape or move one persistent visual assembly. Apple's [adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) recommends sparing use of custom glass and avoiding extra custom backgrounds over system control and toolbar effects.

The visible effect depends on the backdrop, window activation, appearance, accessibility settings, and system rendering. The [historical sidebar inspection](../../../../docs/investigations/2026-09-sidebar-glass.md) found inactive-window screenshots flatter and grayer than active-window screenshots. A white background may show a subtle material. Diagnose the actual view/style and activation state before layering on extra opacity, borders, or fake blur.

For multiple neighboring **native** glass regions, consider [`NSGlassEffectContainerView`](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview):

- Put the descendant effects in the container's `contentView`; the container elevates those descendants above that content view and processes similar effects as a batch. Merely adding the container as an unrelated sibling does not give those effects its grouping behavior.
- [`spacing`](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/spacing) is the proximity threshold for eligible effects. The documented default of zero still batches eligible effects while avoiding nearby shape merging and distortion. Raise it only for an intended merge, then inspect the unfused rest state and the moving overlap; a large threshold can make separate controls read as one before the user acts.
- Similarity and proximity are framework decisions. The container is not an identity, movement, or guaranteed-fusion API. Keep one container around each intended cluster and separate independent clusters when they should not visually join. Batch processing may reduce rendering passes, but profile before making a performance claim.

The original single-toggle accessory needed no merging container. The current creation-capsule design uses the SwiftUI equivalent described next. For persistent SwiftUI guests and symbol sequencing, use [fused-glass-morph](../../fused-glass-morph/SKILL.md) and its [fusion rules](../../fused-glass-morph/references/fusion-rules.md) rather than translating AppKit `spacing` directly into a particular SwiftUI animation duration.

## Separate SwiftUI hosting trees

An `NSHostingView` installed in an AppKit titlebar accessory is a separate hosting tree. Do not assume the workspace's SwiftUI environment automatically reaches it. Commander's [live probe](../../../../Commander/Views/SidebarToolbarMotion.swift) forwards `context.environment` when it updates the existing host root, and the [hosted controls](../../../../Commander/Views/SidebarToolbarControls.swift) apply those values to their tree. That keeps appearance, accessibility settings such as Reduce Motion, and app-provided actions/models aligned with the workspace.

Update the existing `NSHostingView.rootView` as environment values or presentation change; do not replace the hosting view, native button, or `@Namespace` simply to refresh them. This preserves a control and its glass identity through window or thread updates. Confirm the hosted content's appearance, actions, keyboard focus, and accessibility in the running window, because a correct static glass frame does not prove the separate tree received the intended environment.

## SwiftUI equivalents and boundaries

For a wholly SwiftUI control, prefer the platform's glass button style or supported glass-effect modifier. Check the current SDK and [SwiftUI motion guidance](motion-engines.md) before choosing `.buttonStyle(.glass)`, `glassEffect`, an interactive `Glass`, or a `GlassEffectContainer` design. Read [the fused-glass skill](../../fused-glass-morph/SKILL.md) for effect identity, changing geometry, and foreground timing.

SwiftUI glass identities and matched-geometry effects help coordinate appropriate transitions among distinct effects. They do not make an AppKit toolbar item's anchor follow a continuous path, and they are not a substitute for keeping an existing control alive. Avoid wrapping an already-glass native toolbar item in another material unless the design explicitly requires it.

## Commander integration

The current persistent fusion, measured geometry, full hosting-environment bridge, and early toggle trigger are documented in [workspace chrome](../../../../docs/workspace-chrome.md). Prior conditional-transition, grouping-identity, and environment experiments live in [the dated investigation](../../../../docs/investigations/2026-09-sidebar-glass.md). Use the linked production source for current constants and ownership.

## Validation for a glass change

1. Build against the actual deployment target.
2. Inspect expanded and collapsed states with an active window; also check inactive appearance when relevant.
3. Click through the glass and verify actual collapse state changed.
4. Confirm the outer effect and button stay together during travel.
5. Re-run the existing sidebar regression if hierarchy, size, or movement changed.
6. For broader reuse, cover dark appearance, Reduce Transparency/Increase Contrast, Reduce Motion, keyboard focus, and fullscreen/titlebar behavior. The historical single-control inspection did not establish all these behaviors; run the relevant checks for the implementation being changed.

Primary sources: [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview), [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview), [NSVisualEffectView vibrancy guidance](https://developer.apple.com/documentation/appkit/nsvisualeffectview), [NSButton](https://developer.apple.com/documentation/appkit/nsbutton), and [Liquid Glass adoption](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). Check exact availability in the selected SDK declaration.
