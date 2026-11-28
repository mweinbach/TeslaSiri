# Applying Apple's custom Liquid Glass guidance

Use this reference when starting a custom control or reviewing whether its material and hierarchy are appropriate. It translates [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) into engineering choices; it does not replace the page's API documentation. For moving geometry use [fusion rules](fusion-rules.md), for content use [morph and icons](morph-and-icons.md), and for failures use [morph review](morph-review.md).

Apple defines the material and transition behavior. Keeping mounted Commander guests, preserving transcript insets, and choosing foreground reveal points are project practices. A recorded animation shows a visual goal; it cannot establish the implementation behind it.

## Start with the control's role

| Role | Starting point | Reason to add a custom effect |
| --- | --- | --- |
| An ordinary action | A native `Button`, with `.glass` or `.glassProminent` where appropriate | The action participates in a custom fused group or needs an app-specific shape and geometry path. |
| A menu, popover, toolbar, or sidebar | The standard presentation or structure | A specific product interaction requires a custom surface. First inspect what the system already supplies. |
| Several related floating actions | One local glass container around the related effects | They need coherent rendering, proximity fusion, or effect transitions. Each action still owns its semantics. |
| Reading content, transcript entries, file rows, or nested cards | The existing content design | A navigation/control role justifies glass; translucency alone is not a reason. |

Apple places Liquid Glass in the navigation and control layer. Do not turn every transcript item or Files row into floating glass. Preserve Commander's established content hierarchy and density. See [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [HIG materials](https://developer.apple.com/design/human-interface-guidelines/materials).

## Choose material and emphasis

| Choice | Use when | Review consequence |
| --- | --- | --- |
| `.regular` | Text, symbols, and everyday controls need adaptation to varied content | Start here for Commander chrome. Inspect legibility while content moves underneath. |
| `.clear` | A control intentionally sits over rich photography or video and should expose that media | This is not a stronger blur or a generic fix for weak contrast. Bright media may need a contrast treatment; dark media may not. |
| `.tint(...)` | Color communicates a primary action or meaningful status | Judge the whole glass surface and nearby controls together. Many colored surfaces compete for attention. |
| `.interactive()` | A custom action surface needs the material's pointer/touch feedback | It provides visual response, not a button action, hit region, keyboard handler, or accessibility label. |
| `.identity` | A supported interaction deliberately needs an unaffected material state | It is an API identity effect, not a third everyday material style or a substitute for removing inactive semantics. |

The [regular](https://developer.apple.com/documentation/swiftui/glass/regular), [clear](https://developer.apple.com/documentation/swiftui/glass/clear), [interactive](https://developer.apple.com/documentation/swiftui/glass/interactive(_:)), and [identity](https://developer.apple.com/documentation/swiftui/glass/identity) APIs define those choices. HIG materials discusses contrast treatment over bright media; any dimming belongs to that media context, not as a universal scrim behind Commander's controls.

Prefer semantic foreground styling such as `.primary` to hardcoded white symbols. Keep text and symbols inside the glass-bearing view so its foreground treatment can adapt them. Semantic tint can emphasize a primary action; avoid compensating for a bad material choice by assigning bright colors to every glyph. See [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) and [HIG color](https://developer.apple.com/design/human-interface-guidelines/color).

Commander's persistent fusion recipe is regular interactive glass with its existing light tint. The dated [composer investigation](../../../../docs/investigations/2026-09-composer-glass.md) records an unsuccessful heavily tinted clear treatment. That observation does not prove that all clear effects are incapable of fusing.

## Build the hierarchy deliberately

Work from the inside out:

1. Use `Button`, `Label`, and standard menu semantics for the action/content.
2. Set the foreground font, padding, and intended control frame.
3. Set an explicit content hit shape inside the custom button style when the entire surface should respond.
4. Apply `.glassEffect(recipe, in: shape)` to that sized content.
5. Add effect identity, union, or insertion transition only if the chosen morph path needs it.
6. Position the effect in the surrounding layout and scope its movement locally.

This order makes it possible to answer which size is glass, which area is clickable, and which modifiers the effect captures. Apple says to apply the glass modifier after modifiers affecting appearance. Its example moves an already glass-bearing view with `offset`; that is a positioning operation, not a reason to put foreground padding outside the effect. Avoid adding a second glass background behind a glass-styled button unless a distinct surface is intentional. [Custom-view guide](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views#Combine-multiple-views-with-Liquid-Glass-containers).

An outer `clipShape` or a clipped hosting view can cut off the joining neck or the peeled guest. Clip only the foreground that must stay within its animated shape, and give the material's containing view the required drawing room. An overlay can draw outside its owner's reported layout size; that does not guarantee every ancestor permits drawing or pointer input there. Check the running control near window edges and neighboring panes.

## Use each API for its actual job

| API | What it controls | Common wrong expectation |
| --- | --- | --- |
| `GlassEffectContainer(spacing:)` | Collective rendering and proximity at which descendant effects can join | It does not set `HStack` gaps, arbitrate hit regions, or define a spring. |
| `.glassEffectID(_:in:)` | Effect correspondence during hierarchy transitions/animations | Giving two effects the same ID is not the instruction to make a resting group. Use unique effect identities. |
| `.glassEffectUnion(id:namespace:)` | Several similar contributions form one resting material shape | Changing union membership is not a continuous moving peel. |
| `.glassEffectTransition(.matchedGeometry)` | Geometry matching for a glass effect entering/leaving near another effect | It does not link effects in separate system windows or host containers. |
| `.glassEffectTransition(.materialize)` | Material/content appearance without geometry matching | It is a system material transition, not merely an opacity modifier. |
| `.matchedGeometryEffect(...)` | General SwiftUI view geometry correspondence | It is a separate mechanism; adding it to glass does not automatically improve a glass transition. |
| `.contentTransition(...)` / symbol replacement | Content changing inside a persistent view | It does not fuse glass surfaces or choose which of two actions survives. |

Keep these namespaces and identities conceptually distinct, even when the APIs use the same `Namespace.ID` type. Do not stack general matched geometry, an insertion transition, and mounted-frame motion on the same property without a clear reason. Choose one geometry owner and inspect its intermediate rendering before adding another effect. [Glass effect transitions](https://developer.apple.com/documentation/swiftui/glasseffecttransition), [union](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)), and [general matched geometry](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)).

## Adapt the examples

[GlassMorphExamples.swift](../examples/GlassMorphExamples.swift) contains four distinct experiments:

- `PersistentGlassPairExample` keeps both effects and their IDs mounted. A leaf using `@Animatable` synthesis derives guest size, position, and glyph opacity from its interpolated `progress`. The target stored in `@State` is not a frame-by-frame measurement. The secondary action is enabled after a revision-checked completion, while the primary toggle remains available for reversal. This conservative activation policy is a fixture choice; a real control can activate sooner if its visible and clickable region is already unambiguous.
- `InsertedGlassActionExample` truly inserts/removes a secondary action near its source and selects a glass effect transition. It has intentional layout redistribution and is unsuitable as a direct replacement for a composer guest whose transcript inset must remain fixed.
- `StagedLensCardExample` turns a glyph in a host's glass into a round lens that grows while it travels, carries its card's content magnified and blurred, and takes the card's shape. One `@Animatable` value and one spring per direction drive every stage through windows of that value. [Lens morph](lens-morph.md) explains the choices. It omits the Mac's press-to-reopen and the iOS safe-area-bar targets.
- `StaticGlassUnionExample` uses unique effect IDs and one shared union ID. Its two actions retain separate labels and hit regions even though the material is one resting shape.

The fixture dimensions, spacing, spring, and opacity thresholds demonstrate relationships, not Commander tokens or Apple timing requirements. The persistent example keeps interpolation data unbounded and clamps its rendered geometry during overshoot; choose that behavior deliberately if elastic motion is part of the product. Its data type is explicitly `nonisolated`, while its view body remains on the main actor. This satisfies the interpolation protocol under Swift 6 isolation; use the selected SDK/compiler rather than copying the syntax into an older toolchain. It snaps geometry under Reduce Motion and invalidates completion when intent, motion preference, or lifetime changes. It does not implement a real menu, native focus transfer, clipping at a window boundary, or the existing composer scroll contract.

## Keep rendering and updates economical

Group effects that should interact in one local container. Avoid a container per glyph or row, and avoid spreading a related group across unrelated containers. A single app-wide container is not a requirement: separate clusters may have independent rendering and semantics. Apple warns about both excessive containers and many effects outside containers, and recommends limiting simultaneous onscreen effects. [Custom-view performance guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views#Optimize-performance-when-using-Liquid-Glass-effects).

Separate material cost from view-update cost. If a transcript streams, the small glass leaf should not read every token, per-pixel scroll offset, or unrelated store change. Map geometry into the few meaningful values the leaf needs. Keep animation interpolation free of store writes, file operations, and native hierarchy creation. For a hitch, measure the trigger and rendering with [performance profiling](../../../../docs/performance-profiling.md); a smaller spring duration cannot repair expensive frame work.

## Accessibility is part of the destination

Standard components adapt to system preferences. A custom geometry animation still needs its own Reduce Motion policy; an icon's opacity does not remove its action or focus. Preserve action labels and destination meaning, remove inactive guests from interaction/accessibility, and test Reduce Transparency and increased contrast rather than guessing what material the system will display. On macOS, the cross-fade preference follows Reduce Motion. Read the animation skill's [content and accessibility guidance](../../swiftui-animation-control/references/content-and-accessibility.md) for content fallback and interrupted preference changes. [Adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass#Visual-refresh).

SwiftUI's core glass APIs used here are available on macOS 26; Commander targets macOS 27. Confirm declarations in the selected SDK for new overloads and gate native AppKit features separately. See the [SDK research workflow](../../nssplitview-control/references/xcode-research.md). Compilation confirms names, types, and availability; [morph review](morph-review.md) supplies the visual and interaction checks that compilation cannot establish.
