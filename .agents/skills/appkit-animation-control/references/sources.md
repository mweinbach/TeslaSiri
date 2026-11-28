# AppKit animation source ledger

Researched 2026-09-13 with Xcode MCP documentation search, installed Xcode 27.0 (27A266a) declarations, and Apple's archived Core Animation guide. Archived concepts are paired with current API declarations; old Objective-C syntax is not copied as modern Swift guidance.

| Source | Claim supported |
| --- | --- |
| [NSAnimationContext](https://developer.apple.com/documentation/appkit/nsanimationcontext) | Nested contexts and inherited timing |
| [runAnimationGroup](https://developer.apple.com/documentation/appkit/nsanimationcontext/runanimationgroup(_:completionhandler:)) | Group semantics and completion |
| [completionHandler](https://developer.apple.com/documentation/appkit/nsanimationcontext/completionhandler) | Main-thread callback after completion/cancellation; immediate cases |
| [allowsImplicitAnimation](https://developer.apple.com/documentation/appkit/nsanimationcontext/allowsimplicitanimation) | Implicit changes; local header clarifies layer backing and default false |
| [NSAnimatablePropertyContainer](https://developer.apple.com/documentation/appkit/nsanimatablepropertycontainer) | Supported properties, animator proxies, custom animations |
| [layoutSubtreeIfNeeded](https://developer.apple.com/documentation/appkit/nsview/layoutsubtreeifneeded()) | Resolve pending subtree layout |
| [NSAnimationContext.animate](https://developer.apple.com/documentation/appkit/nsanimationcontext/animate(_:changes:completion:)) | SwiftUI curves, smooth retargeting, in-process implementation |
| [Unifying your app's animations](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations) | SwiftUI/AppKit bridge and implementation distinctions |
| [NSViewRepresentableContext.animate](https://developer.apple.com/documentation/swiftui/nsviewrepresentablecontext/animate(changes:completion:)) | Current transaction timing in AppKit |
| [CALayer.presentation](https://developer.apple.com/documentation/quartzcore/calayer/presentation()) | Approximate visible state snapshot |
| [CABasicAnimation](https://developer.apple.com/documentation/quartzcore/cabasicanimation) | Explicit interpolation endpoints |
| [CASpringAnimation](https://developer.apple.com/documentation/quartzcore/caspringanimation) | Physical spring parameters and settling |
| [CAKeyframeAnimation](https://developer.apple.com/documentation/quartzcore/cakeyframeanimation) | Values, paths, modes, times |
| [CAAnimationDelegate](https://developer.apple.com/documentation/quartzcore/caanimationdelegate) | Start/stop and completion status |
| [Advanced Animation Tricks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html) | Local time, delay, backwards fill, pause/resume, explicit transactions |
| [Animating Layer Content](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CreatingBasicAnimations/CreatingBasicAnimations.html) | Explicit animation and model-state responsibility |
| [Reduce Motion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion) | AppKit system motion setting |

## Verified availability details

- Classic context/proxy and Core Animation recipes use long-standing APIs; sample compilation baseline is macOS 14 with Swift 6 checking.
- `NSAnimationContext.animate(_:changes:completion:)` is a SwiftUI extension on AppKit, **macOS 15.0+**. Import SwiftUI.
- Both representable context animation helpers are **macOS 15.0+** in the installed SDK, with implementations back-deployed before 15.4. A compatible SDK is still required.
- SwiftUI-backed AppKit animation does not provide a render-server `CAAnimation`. Layer-clock scrubbing applies to the explicit Core Animation route, not that modern bridge.

## Research queries

```text
AppKit: NSAnimationContext completionHandler cancelled main thread
AppKit: NSAnimationContext animate changes SwiftUI retarget velocity
SwiftUI: NSViewRepresentableContext animate transaction
QuartzCore: CALayer presentation current state
QuartzCore: CAAnimationDelegate animationDidStop finished
```

If a query returns `NSAnimation` instead of `NSAnimationContext`, narrow it. `NSAnimation.stop()` and `NSViewAnimation` behavior are not universal rules for other animation systems.
