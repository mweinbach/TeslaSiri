# SwiftUI motion diagnosis and source ledger

## Symptom map

| Symptom | Inspect | Likely correction |
| --- | --- | --- |
| Unrelated text/spacing animates | Root `.animation`, same-update changes | Narrow scope with an effect closure or smaller subtree |
| Transition never runs | No insertion/removal, no animated transaction | Match mechanism to actual state/identity change |
| Outgoing view disappears instantly | z-order and clipping | Keep outgoing drawing visible for the intended transition |
| Spring resets on every data update | Unstable identity, repeated trigger or representable writes | Preserve identity and apply only changed targets |
| Completion hides/reorders wrong content | Stale captured request | Guard revision and current intent |
| `.removed` never seems to complete | Continuing animations on affected properties | Choose logical completion or a different semantic boundary |
| Gesture release jumps | Separate gesture-state reset and persistent-state transactions | Reconcile reset/handoff deliberately |
| Drag re-grab jumps to endpoint | Reading target state as presentation | Use an interaction architecture that exposes continuous progress |
| Custom shape doesn't interpolate | Missing/incorrect animatable channels | Macro or correct explicit data mapping |
| Animation hitches despite simple curve | Expensive body, layout, text, path or keyframe content | Profile updates/render work; simplify per-frame computation |
| Reduce Motion still bounces | Independent local animation/phase/keyframe trigger | Route reduced-motion policy at the actual owner |
| Removing layer animations does nothing | SwiftUI engine is not a render-server CAAnimation | Retarget through state/transaction |

## A focused debugging sequence

1. Reproduce one action with state identity and all animation modifiers visible in a small example.
2. Compare immediate update with animated update. If immediate geometry is wrong, correct layout first.
3. Trigger an unrelated state update simultaneously to detect scope leakage.
4. Reverse at several points and repeat while content updates.
5. Inspect reduced-motion behavior and view disappearance/reappearance.
6. Profile only after the effect's state, identity, and geometry are correct.

Use a real macOS window for toolbar/sidebar/live-resize effects. A SwiftUI preview cannot establish the full window behavior from a static image. Use the shared [Xcode workflow](../../nssplitview-control/references/xcode-research.md) for documentation, API checks, previews, and actual motion verification.

## Availability table

Checked against Xcode 27.0 (27A266a) SDK declarations on 2026-09-13. Compile for the project's actual target; do not infer availability from a tutorial's age.

| Feature | Deployment baseline / qualification |
| --- | --- |
| `withAnimation`, `Animatable`, basic transactions | Original SwiftUI-era APIs |
| `matchedGeometryEffect` | macOS 11 / iOS 14 |
| `contentTransition` | macOS 13 / iOS 16 |
| Scoped animation/transaction closures | macOS 14 / iOS 17 |
| Duration/bounce springs and smooth/snappy/bouncy families | macOS 14 / iOS 17 |
| Animation completion criteria and transaction completions | macOS 14 / iOS 17 |
| Phase/keyframe animators and `CustomAnimation` | macOS 14 / iOS 17 |
| AppKit SwiftUI-animation bridge | macOS 15; import SwiftUI |
| `AnimatableValues` | macOS 26 / iOS 26 |
| `@Animatable` / `@AnimatableIgnored` | Requires a supporting SDK/compiler; installed macro declarations back-deploy, so verify expansion for older targets |

If adopting SDK-27-specific behavior such as state macros or changed builder overloads, use the existing `swiftui-whats-new-27` skill for that migration. This pack is primarily about animation control, not a blanket SDK migration.

## Primary sources and what they support

| Source | Topic |
| --- | --- |
| [Animations](https://developer.apple.com/documentation/swiftui/animations) | Framework animation surface |
| [withAnimation](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)) | Explicit state-change transaction |
| [Scoped animation](https://developer.apple.com/documentation/swiftui/view/animation(_:body:)) | Modifier-level animation scope |
| [Transaction](https://developer.apple.com/documentation/swiftui/transaction) | Animation metadata and overrides |
| [Scoped transaction](https://developer.apple.com/documentation/swiftui/view/transaction(_:body:)) | Per-effect transaction mutation |
| [AnimationCompletionCriteria](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria) | Logical versus full removal |
| [Logically complete](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria/logicallycomplete) | Later animations don't extend the original logical callback |
| [Removed](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria/removed) | Subsequent animations can delay removal completion |
| [Matched geometry](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)) | Window-space frames, geometry versus rendering, source uniqueness |
| [Spring](https://developer.apple.com/documentation/swiftui/animation/spring(duration:bounce:blendduration:)) | Perceptual duration, bounce, retargeting |
| [Controlling timing and movement](https://developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations) | Phases and independent keyframe tracks |
| [Triggered keyframes](https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)) | Current-value replacement, velocity, retained endpoints |
| [Animatable](https://developer.apple.com/documentation/swiftui/animatable) | Custom interpolation channels |
| [AnimatableValues](https://developer.apple.com/documentation/swiftui/animatablevalues) | Modern multi-value vector container |
| [CustomAnimation](https://developer.apple.com/documentation/swiftui/customanimation) | Pure custom timing, velocity and merge contracts |
| [GestureState](https://developer.apple.com/documentation/swiftui/gesturestate) | Gesture lifetime and reset transaction |
| [Unifying animations](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations) | Native-framework bridging and implementation distinctions |

## Recommended Apple sessions

- [Explore SwiftUI animation — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10156/): data flow, transactions, animatable values, and animation mechanics.
- [Enhance your UI animations and transitions — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10145/): cross-framework animation and transitions; linked by Apple's unified-animation article.

The detailed references are project-authored summaries grounded in symbol documentation and SDK checks. Apple's installed `swiftui-specialist` reference remains authoritative for its custom-`Animatable` recommendations. Code examples need runtime inspection in the actual component before making performance or visual-quality claims.
